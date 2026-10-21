//
//  CompleteLinkClustering.swift
//  PicSmart
//

import Foundation

struct CompleteLinkClustering: Sendable {
    /// Clusters items using complete-linkage (clique requirement).
    /// Every member in a cluster must be pairwise similar to every other member in that cluster,
    /// completely preventing similarity chaining creep across large photo libraries.
    static func cluster<T: Sendable>(
        items: [T],
        isPairSimilar: (T, T) -> Bool
    ) -> [[T]] {
        var clusters: [[T]] = []
        
        for item in items {
            // Find an existing cluster where this item is similar to ALL members
            if let index = clusters.firstIndex(where: { cluster in
                cluster.allSatisfy { member in
                    isPairSimilar(item, member)
                }
            }) {
                clusters[index].append(item)
            } else {
                clusters.append([item])
            }
        }
        
        // Return only groups containing 2 or more items
        return clusters.filter { $0.count > 1 }
    }
}
