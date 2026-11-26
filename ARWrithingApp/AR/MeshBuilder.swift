//
//  MeshBuilder.swift
//  ARWrithingApp
//
//  Created by Airi Nakanishi on 2026/07/14.
//

import RealityKit
import UIKit

struct MeshBuilder {
    var positions: [SIMD3<Float>] = []
    var indices: [UInt32] = []
    
    mutating func addQuad(p0: SIMD3<Float>, p1: SIMD3<Float>, p2: SIMD3<Float>, p3: SIMD3<Float>) {
        let startIdx = UInt32(positions.count)
        positions.append(contentsOf: [p0, p1, p2, p3])
        indices.append(contentsOf: [startIdx, startIdx+2, startIdx+1, startIdx, startIdx+3, startIdx+2])
    }
    
    mutating func addLine(from: SIMD2<Float>, to: SIMD2<Float>, thickness: Float) {
        let dir = to - from
        let length = simd_length(dir)
        guard length > 0 else { return }
        let normDir = dir / length
        let perp = SIMD2<Float>(-normDir.y, normDir.x) * (thickness / 2.0)
        
        let p0 = SIMD3<Float>(from.x - perp.x, from.y - perp.y, 0)
        let p1 = SIMD3<Float>(from.x + perp.x, from.y + perp.y, 0)
        let p2 = SIMD3<Float>(to.x + perp.x, to.y + perp.y, 0)
        let p3 = SIMD3<Float>(to.x - perp.x, to.y - perp.y, 0)
        
        addQuad(p0: p0, p1: p1, p2: p2, p3: p3)
    }
    
    mutating func addDashedLine(from: SIMD2<Float>, to: SIMD2<Float>, thickness: Float, dashLength: Float, gapLength: Float) {
        let dir = to - from
        let totalLength = simd_length(dir)
        guard totalLength > 0 else { return }
        let normDir = dir / totalLength
        
        var currentLen: Float = 0.0
        while currentLen < totalLength {
            let start = from + normDir * currentLen
            let thisDashLen = min(dashLength, totalLength - currentLen)
            let end = start + normDir * thisDashLen
            addLine(from: start, to: end, thickness: thickness)
            currentLen += dashLength + gapLength
        }
    }
    
    mutating func addDot(center: SIMD2<Float>, radius: Float) {
        let p0 = SIMD3<Float>(center.x + radius, center.y - radius, 0)
        let p1 = SIMD3<Float>(center.x - radius, center.y - radius, 0)
        let p2 = SIMD3<Float>(center.x - radius, center.y + radius, 0)
        let p3 = SIMD3<Float>(center.x + radius, center.y + radius, 0)
        addQuad(p0: p0, p1: p1, p2: p2, p3: p3)
    }
    
    func generate() -> MeshResource? {
        guard !positions.isEmpty else { return nil }
        var desc = MeshDescriptor(name: "mergedMesh")
        desc.positions = MeshBuffers.Positions(positions)
        desc.primitives = .triangles(indices)
        return try? MeshResource.generate(from: [desc])
    }
}
