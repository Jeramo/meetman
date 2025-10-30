//
//  Clustering.swift
//  MeetingCopilot
//
//  Speaker clustering using cosine distance k-means
//

import Accelerate
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.jeramo.meetingman", category: "diarization")

/// Speaker clustering algorithms
public enum Clustering {

    /// Cluster embeddings using k-means with cosine distance
    ///
    /// - Parameters:
    ///   - embeddings: Array of embedding vectors (should be normalized)
    ///   - maxClusters: Maximum number of clusters to consider
    /// - Returns: Array of cluster labels (indices) for each embedding
    public static func agglomerativeCosine(
        _ embeddings: [[Float]],
        maxClusters: Int = 6
    ) -> [Int] {
        guard !embeddings.isEmpty else { return [] }
        guard embeddings.count > 1 else { return [0] }

        // Estimate optimal k using elbow heuristic
        let k = estimateOptimalK(embeddings, maxK: maxClusters)

        logger.info("Clustering \(embeddings.count) embeddings into \(k) speakers")

        // Run k-means with cosine distance
        let labels = kMeansCosine(embeddings, k: k, maxIterations: 50)

        // Log cluster distribution
        let distribution = labels.reduce(into: [Int: Int]()) { counts, label in
            counts[label, default: 0] += 1
        }
        logger.debug("Cluster distribution: \(distribution)")

        return labels
    }

    // MARK: - K-Means with Cosine Distance

    /// K-means clustering using cosine distance (1 - cosine similarity)
    private static func kMeansCosine(
        _ embeddings: [[Float]],
        k: Int,
        maxIterations: Int = 50,
        tolerance: Float = 1e-4
    ) -> [Int] {
        let n = embeddings.count
        guard n >= k else {
            // Not enough samples, assign each to its own cluster
            return Array(0..<n)
        }

        // Initialize centroids using k-means++
        var centroids = initializeCentroidsKMeansPlusPlus(embeddings, k: k)
        var labels = [Int](repeating: 0, count: n)
        var previousLabels = [Int](repeating: -1, count: n)

        for iteration in 0..<maxIterations {
            // Assignment step: assign each embedding to nearest centroid
            for i in 0..<n {
                var maxSimilarity: Float = -1
                var bestCluster = 0

                for j in 0..<k {
                    let similarity = cosineSimilarity(embeddings[i], centroids[j])
                    if similarity > maxSimilarity {
                        maxSimilarity = similarity
                        bestCluster = j
                    }
                }

                labels[i] = bestCluster
            }

            // Check convergence
            if labels == previousLabels {
                logger.debug("K-means converged at iteration \(iteration)")
                break
            }

            previousLabels = labels

            // Update step: recompute centroids
            for j in 0..<k {
                let clusterIndices = labels.enumerated().compactMap { $0.element == j ? $0.offset : nil }

                if !clusterIndices.isEmpty {
                    // Compute mean of embeddings in cluster
                    let clusterEmbeddings = clusterIndices.map { embeddings[$0] }
                    centroids[j] = meanVector(clusterEmbeddings)
                }
            }
        }

        return labels
    }

    /// Initialize centroids using k-means++ algorithm
    private static func initializeCentroidsKMeansPlusPlus(
        _ embeddings: [[Float]],
        k: Int
    ) -> [[Float]] {
        let n = embeddings.count
        var centroids: [[Float]] = []

        // Choose first centroid randomly
        let firstIndex = Int.random(in: 0..<n)
        centroids.append(embeddings[firstIndex])

        // Choose remaining k-1 centroids
        for _ in 1..<k {
            var distances = [Float](repeating: 0, count: n)

            // Compute distance to nearest centroid for each point
            for i in 0..<n {
                var minDistance: Float = Float.infinity

                for centroid in centroids {
                    let similarity = cosineSimilarity(embeddings[i], centroid)
                    let distance = 1.0 - similarity // Cosine distance
                    minDistance = min(minDistance, distance)
                }

                distances[i] = minDistance
            }

            // Choose next centroid with probability proportional to distance squared
            let distancesSquared = distances.map { $0 * $0 }
            let totalWeight = distancesSquared.reduce(0, +)

            guard totalWeight > 0 else {
                // Fallback: choose random point
                let randomIndex = Int.random(in: 0..<n)
                centroids.append(embeddings[randomIndex])
                continue
            }

            let threshold = Float.random(in: 0..<totalWeight)
            var cumulative: Float = 0

            for i in 0..<n {
                cumulative += distancesSquared[i]
                if cumulative >= threshold {
                    centroids.append(embeddings[i])
                    break
                }
            }
        }

        return centroids
    }

    // MARK: - Optimal K Estimation

    /// Estimate optimal number of clusters using elbow heuristic
    private static func estimateOptimalK(
        _ embeddings: [[Float]],
        maxK: Int
    ) -> Int {
        let n = embeddings.count

        // Simple heuristics based on data size
        if n <= 4 {
            return 2
        } else if n <= 12 {
            return min(2, maxK)
        } else if n <= 30 {
            return min(3, maxK)
        } else if n <= 60 {
            return min(4, maxK)
        } else {
            // For larger datasets, try to find elbow
            let maxKToTry = min(maxK, n / 10, 6)
            return findElbow(embeddings, maxK: maxKToTry)
        }
    }

    /// Find elbow point in within-cluster dispersion curve
    private static func findElbow(
        _ embeddings: [[Float]],
        maxK: Int
    ) -> Int {
        var dispersions: [Float] = []

        for k in 1...maxK {
            let labels = kMeansCosine(embeddings, k: k, maxIterations: 20)
            let dispersion = computeDispersion(embeddings, labels: labels, k: k)
            dispersions.append(dispersion)
        }

        // Find elbow using rate of change
        var bestK = 2
        var maxRateChange: Float = 0

        for k in 1..<maxK - 1 {
            let rateChange = abs(dispersions[k] - dispersions[k - 1]) - abs(dispersions[k + 1] - dispersions[k])
            if rateChange > maxRateChange {
                maxRateChange = rateChange
                bestK = k + 1 // +1 because k is 0-indexed but represents k-1 clusters
            }
        }

        return max(2, min(bestK, maxK))
    }

    /// Compute within-cluster dispersion (using cosine distance)
    private static func computeDispersion(
        _ embeddings: [[Float]],
        labels: [Int],
        k: Int
    ) -> Float {
        var totalDispersion: Float = 0

        for clusterID in 0..<k {
            let clusterIndices = labels.enumerated().compactMap { $0.element == clusterID ? $0.offset : nil }

            if clusterIndices.isEmpty { continue }

            let clusterEmbeddings = clusterIndices.map { embeddings[$0] }
            let centroid = meanVector(clusterEmbeddings)

            for embedding in clusterEmbeddings {
                let similarity = cosineSimilarity(embedding, centroid)
                let distance = 1.0 - similarity
                totalDispersion += distance
            }
        }

        return totalDispersion
    }

    // MARK: - Vector Operations

    /// Compute cosine similarity between two vectors
    private static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))

        // If vectors are already normalized (unit length), dot product = cosine similarity
        // For safety, compute magnitudes
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0
        vDSP_svesq(a, 1, &magnitudeA, vDSP_Length(a.count))
        vDSP_svesq(b, 1, &magnitudeB, vDSP_Length(b.count))

        let magnitude = sqrtf(magnitudeA) * sqrtf(magnitudeB)
        guard magnitude > 0 else { return 0 }

        return dotProduct / magnitude
    }

    /// Compute mean of multiple vectors
    private static func meanVector(_ vectors: [[Float]]) -> [Float] {
        guard !vectors.isEmpty else { return [] }
        guard vectors.count > 1 else { return vectors[0] }

        let dim = vectors[0].count
        var mean = [Float](repeating: 0, count: dim)

        // Sum all vectors
        for vector in vectors {
            vDSP_vadd(mean, 1, vector, 1, &mean, 1, vDSP_Length(dim))
        }

        // Divide by count
        var count = Float(vectors.count)
        vDSP_vsdiv(mean, 1, &count, &mean, 1, vDSP_Length(dim))

        // Normalize to unit length
        var magnitude: Float = 0
        vDSP_svesq(mean, 1, &magnitude, vDSP_Length(dim))
        magnitude = sqrtf(magnitude)

        if magnitude > 0 {
            var normalized = [Float](repeating: 0, count: dim)
            vDSP_vsdiv(mean, 1, &magnitude, &normalized, 1, vDSP_Length(dim))
            return normalized
        }

        return mean
    }
}
