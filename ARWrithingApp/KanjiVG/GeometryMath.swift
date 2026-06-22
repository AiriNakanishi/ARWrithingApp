import Foundation
import simd

struct GeometryMath {
    static func segmentsIntersect(p1: SIMD2<Float>, p2: SIMD2<Float>, p3: SIMD2<Float>, p4: SIMD2<Float>) -> SIMD2<Float>? {
        let d = (p2.x - p1.x) * (p4.y - p3.y) - (p2.y - p1.y) * (p4.x - p3.x)
        if abs(d) < 0.0001 { return nil }
        let u = ((p3.x - p1.x) * (p4.y - p3.y) - (p3.y - p1.y) * (p4.x - p3.x)) / d
        let v = ((p3.x - p1.x) * (p2.y - p1.y) - (p3.y - p1.y) * (p2.x - p1.x)) / d
        
        if u >= 0.0 && u <= 1.0 && v >= 0.0 && v <= 1.0 {
            return SIMD2<Float>(p1.x + u * (p2.x - p1.x), p1.y + u * (p2.y - p1.y))
        }
        return nil
    }

    static func distanceSquared(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        return (a.x - b.x)*(a.x - b.x) + (a.y - b.y)*(a.y - b.y)
    }

    static func pointToSegmentDistance(p: SIMD2<Float>, v: SIMD2<Float>, w: SIMD2<Float>) -> Float {
        let l2 = distanceSquared(v, w)
        if l2 == 0 { return distance(p, v) }
        var t = ((p.x - v.x) * (w.x - v.x) + (p.y - v.y) * (w.y - v.y)) / l2
        t = max(0, min(1, t))
        let projection = SIMD2<Float>(v.x + t * (w.x - v.x), v.y + t * (w.y - v.y))
        return distance(p, projection)
    }
    
    static func distance(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
        return sqrt((a.x - b.x)*(a.x - b.x) + (a.y - b.y)*(a.y - b.y))
    }
}
