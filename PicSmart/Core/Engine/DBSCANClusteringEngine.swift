//
//  DBSCANClusteringEngine.swift
//  PicSmart
//

import Foundation
import Photos
import Accelerate

/// Biometric face representation ready for spatial density clustering.
struct BiometricFaceItem: Sendable {
    let id: String
    let asset: PHAsset
    let boundingBox: CGRect
    let captureQuality: Float
    let embedding: [Float]
}

/// A dense cluster of biometric face instances representing an identified human identity.
struct ClusteredIdentity: Sendable {
    let clusterId: Int
    let avatarFace: BiometricFaceItem
    let memberFaces: [BiometricFaceItem]
    let centroid: [Float]
    
    var uniqueAssets: [PHAsset] {
        var seen = Set<String>()
        var assets: [PHAsset] = []
        for face in memberFaces {
            if seen.insert(face.asset.localIdentifier).inserted {
                assets.append(face.asset)
            }
        }
        return assets
    }
}

/// Output of DBSCAN clustering containing grouped identities and noise/singleton faces.
struct DBSCANClusteringOutput: Sendable {
    let identities: [ClusteredIdentity]
    let unclusteredFaces: [BiometricFaceItem]
}

/// High-performance Density-Based Spatial Clustering of Applications with Noise (DBSCAN)
/// driven by Apple Accelerate vectorized Cosine Distance routines.
struct DBSCANClusteringEngine: Sendable {
    
    /// Vectorized cosine distance between two unit-normalized embeddings: 1.0 - dot(a, b).
    @inlinable
    static func cosineDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 1.0 }
        var dot: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dot, vDSP_Length(a.count))
        return max(0.0, 1.0 - dot)
    }
    
    /// Groups face embeddings into human identities using DBSCAN.
    /// - Parameters:
    ///   - faces: Array of detected, aligned, and embedded face items.
    ///   - epsilon: Cosine distance neighborhood radius (default 0.40 for MobileFaceNet).
    ///   - minSamples: Minimum number of samples to form a core density point (default 2).
    static func cluster(
        faces: [BiometricFaceItem],
        epsilon: Float = 0.40,
        minSamples: Int = 2
    ) -> DBSCANClusteringOutput {
        let n = faces.count
        guard n > 0 else {
            return DBSCANClusteringOutput(identities: [], unclusteredFaces: [])
        }
        
        var visited = [Bool](repeating: false, count: n)
        var clusterAssignments = [Int](repeating: -1, count: n) // -1 denotes noise / unassigned
        var currentClusterId = 0
        
        func findNeighbors(of index: Int) -> [Int] {
            var neighbors: [Int] = []
            neighbors.reserveCapacity(16)
            let query = faces[index].embedding
            for j in 0..<n {
                let dist = cosineDistance(query, faces[j].embedding)
                if dist <= epsilon {
                    neighbors.append(j)
                }
            }
            return neighbors
        }
        
        for i in 0..<n {
            if visited[i] { continue }
            visited[i] = true
            
            let neighbors = findNeighbors(of: i)
            if neighbors.count < minSamples {
                clusterAssignments[i] = -1 // Noise
            } else {
                let clusterId = currentClusterId
                currentClusterId += 1
                clusterAssignments[i] = clusterId
                
                var seedQueue = [Int]()
                var inQueue = [Bool](repeating: false, count: n)
                
                for neighbor in neighbors where neighbor != i {
                    seedQueue.append(neighbor)
                    inQueue[neighbor] = true
                }
                
                var queueIndex = 0
                while queueIndex < seedQueue.count {
                    let pointIdx = seedQueue[queueIndex]
                    queueIndex += 1
                    
                    if !visited[pointIdx] {
                        visited[pointIdx] = true
                        let pointNeighbors = findNeighbors(of: pointIdx)
                        if pointNeighbors.count >= minSamples {
                            for nextNeighbor in pointNeighbors {
                                if !inQueue[nextNeighbor] && nextNeighbor != i {
                                    seedQueue.append(nextNeighbor)
                                    inQueue[nextNeighbor] = true
                                }
                            }
                        }
                    }
                    
                    if clusterAssignments[pointIdx] == -1 {
                        clusterAssignments[pointIdx] = clusterId
                    }
                }
            }
        }
        
        // Group points by clusterId
        var clusterMembers: [Int: [BiometricFaceItem]] = [:]
        var unclustered: [BiometricFaceItem] = []
        
        for (idx, clusterId) in clusterAssignments.enumerated() {
            if clusterId >= 0 {
                clusterMembers[clusterId, default: []].append(faces[idx])
            } else {
                unclustered.append(faces[idx])
            }
        }
        
        // Build identities and select canonical medoid avatar
        var identities: [ClusteredIdentity] = []
        for (clusterId, members) in clusterMembers {
            guard !members.isEmpty else { continue }
            
            let dim = members[0].embedding.count
            var centroid = [Float](repeating: 0, count: dim)
            for m in members {
                vDSP_vadd(centroid, 1, m.embedding, 1, &centroid, 1, vDSP_Length(dim))
            }
            var scale = 1.0 / Float(members.count)
            vDSP_vsmul(centroid, 1, &scale, &centroid, 1, vDSP_Length(dim))
            
            // Normalize centroid
            var sumSq: Float = 0
            vDSP_svesq(centroid, 1, &sumSq, vDSP_Length(dim))
            let norm = sqrt(sumSq)
            if norm > 1e-6 {
                var invNorm = 1.0 / norm
                vDSP_vsmul(centroid, 1, &invNorm, &centroid, 1, vDSP_Length(dim))
            }
            
            // Select the most central and highest quality face as key avatar
            var bestAvatar = members[0]
            var bestScore: Float = -1.0
            
            for m in members {
                let distToCentroid = cosineDistance(m.embedding, centroid)
                let score = (1.0 - distToCentroid) * 0.7 + m.captureQuality * 0.3
                if score > bestScore {
                    bestScore = score
                    bestAvatar = m
                }
            }
            
            identities.append(ClusteredIdentity(
                clusterId: clusterId,
                avatarFace: bestAvatar,
                memberFaces: members,
                centroid: centroid
            ))
        }
        
        // Sort identities by number of unique photos descending
        identities.sort { $0.uniqueAssets.count > $1.uniqueAssets.count }
        
        return DBSCANClusteringOutput(
            identities: identities,
            unclusteredFaces: unclustered
        )
    }
}
