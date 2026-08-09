import Foundation

struct RetrievedKnowledge: Sendable {
    let citation: AssistantCitation
    let excerpt: String
}

struct MedicalKnowledgeRepository: Sendable {
    private struct Resource: Decodable {
        let version: String
        let entries: [Entry]
    }

    private struct Entry: Decodable, Sendable {
        let id: String
        let title: String
        let publisher: String
        let urlString: String?
        let lastVerified: String
        let reviewStatus: String
        let keywords: [String]
        let excerpt: String
    }

    private let entries: [Entry]

    init(bundle: Bundle = .main) {
        guard let url = bundle.url(
            forResource: "MedicalAssistantKnowledge",
            withExtension: "json"
        ),
              let data = try? Data(contentsOf: url),
              let resource = try? JSONDecoder().decode(Resource.self, from: data)
        else {
            entries = []
            return
        }
        entries = resource.entries
    }

    init(data: Data) throws {
        entries = try JSONDecoder().decode(Resource.self, from: data).entries
    }

    var entryCount: Int { entries.count }

    func retrieve(
        query: String,
        anatomyContext: AssistantAnatomyContext,
        limit: Int = 3
    ) -> [RetrievedKnowledge] {
        let normalizedQuery = query.lowercased()
        let queryTerms = Set(normalizedQuery.components(
            separatedBy: CharacterSet.alphanumerics.inverted
        ).filter { $0.count >= 3 })
        let focusedStructure = anatomyContext.focusedStructure.lowercased()

        return entries.compactMap { entry -> (Int, Entry)? in
            let searchable = ([entry.title, entry.excerpt] + entry.keywords)
                .joined(separator: " ")
                .lowercased()
            var score = queryTerms.reduce(0) { partial, term in
                partial + (searchable.contains(term) ? 1 : 0)
            }
            score += entry.keywords.reduce(0) { partial, keyword in
                partial + (normalizedQuery.contains(keyword.lowercased()) ? 4 : 0)
            }
            if !focusedStructure.isEmpty,
               focusedStructure != "forearm anatomy",
               searchable.contains(focusedStructure) {
                score += 3
            }
            return score > 0 ? (score, entry) : nil
        }
        .sorted {
            if $0.0 == $1.0 { return $0.1.id < $1.1.id }
            return $0.0 > $1.0
        }
        .prefix(max(0, limit))
        .enumerated()
        .map { index, scored in
            let entry = scored.1
            return RetrievedKnowledge(
                citation: AssistantCitation(
                    id: "S\(index + 1)",
                    title: entry.title,
                    publisher: entry.publisher,
                    urlString: entry.urlString,
                    lastVerified: entry.lastVerified,
                    reviewStatus: entry.reviewStatus
                ),
                excerpt: entry.excerpt
            )
        }
    }
}
