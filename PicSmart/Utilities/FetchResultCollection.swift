//
//  FetchResultCollection.swift
//  PicSmart
//

import Photos
import Foundation

/// A lightweight, zero-allocation RandomAccessCollection wrapper around `PHFetchResult<PHAsset>`.
/// Avoids materializing the entire gallery into a Swift array, enabling instant startup and low memory.
struct FetchResultCollection: RandomAccessCollection, Sendable {
    typealias Element = PHAsset
    typealias Index = Int
    
    let fetchResult: PHFetchResult<PHAsset>
    
    var startIndex: Index { 0 }
    var endIndex: Index { fetchResult.count }
    
    subscript(position: Index) -> Element {
        fetchResult.object(at: position)
    }
}
