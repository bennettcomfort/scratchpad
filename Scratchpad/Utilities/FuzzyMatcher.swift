import Foundation

enum FuzzyMatcher {
    /// Scores a candidate against a query. Scoring:
    ///   100 = exact (case-insensitive) match
    ///   80  = query is prefix of candidate
    ///   60  = all query chars appear consecutively in candidate
    ///   40  = all query chars appear in order (subsequence)
    ///   -1  = no match
    static func score(query: String, candidate: String) -> Int {
        let q = query.lowercased()
        let c = candidate.lowercased()

        if q == c { return 100 }
        if c.hasPrefix(q) { return 80 }

        // Consecutive substring match
        if c.contains(q) { return 60 }

        // Subsequence match (chars in order, not necessarily adjacent)
        var qi = q.startIndex
        for ch in c {
            if qi < q.endIndex, ch == q[qi] {
                qi = q.index(after: qi)
            }
        }
        if qi == q.endIndex { return 40 }

        return -1
    }
}
