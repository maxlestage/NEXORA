import Foundation

/// Une erreur renvoyée par GitHub.
public struct GitHubError: Error, Sendable, CustomStringConvertible, LocalizedError {
    public let message: String
    public let status: Int?

    public init(_ message: String, status: Int? = nil) {
        self.message = message
        self.status = status
    }

    public var description: String { status.map { "GitHub \($0) · \(message)" } ?? message }
    public var errorDescription: String? { description }
}

public struct GHUser: Decodable, Sendable, Hashable {
    public let login: String
    public let name: String?
    public let avatarUrl: String?
    public let publicRepos: Int?

    enum CodingKeys: String, CodingKey {
        case login, name, avatarUrl = "avatar_url", publicRepos = "public_repos"
    }
}

public struct Repo: Decodable, Sendable, Hashable, Identifiable {
    public struct Owner: Decodable, Sendable, Hashable {
        public let login: String
    }

    public let id: Int
    public let fullName: String
    public let name: String
    public let owner: Owner
    public let description: String?
    public let isPrivate: Bool
    public let defaultBranch: String?
    public let language: String?
    public let stars: Int?
    public let forks: Int?
    public let openIssues: Int?
    public let htmlUrl: String
    public let pushedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, fullName = "full_name", name, owner, description, isPrivate = "private"
        case defaultBranch = "default_branch", language, stars = "stargazers_count"
        case forks = "forks_count", openIssues = "open_issues_count", htmlUrl = "html_url"
        case pushedAt = "pushed_at"
    }

    public var branch: String { defaultBranch ?? "main" }
}

public struct ContentItem: Decodable, Sendable, Hashable, Identifiable {
    public let name: String
    public let path: String
    /// file, dir, symlink, submodule.
    public let type: String
    public let sha: String
    public let size: Int?

    public var id: String { path }
    public var isDir: Bool { type == "dir" }
}

/// Un fichier lu : son texte et sa version (`sha`), nécessaire pour l'écrire.
public struct FileContent: Sendable, Hashable {
    public let path: String
    public let text: String
    public let sha: String
    public let binary: Bool
}

public struct Issue: Decodable, Sendable, Hashable, Identifiable {
    public struct User: Decodable, Sendable, Hashable {
        public let login: String
    }

    public let id: Int
    public let number: Int
    public let title: String
    public let body: String?
    public let state: String
    public let user: User?
    public let comments: Int?
    public let htmlUrl: String?
    public let updatedAt: String?
    public let pullRequest: PullRef?

    public struct PullRef: Decodable, Sendable, Hashable {
        public let url: String?
    }

    enum CodingKeys: String, CodingKey {
        case id, number, title, body, state, user, comments, htmlUrl = "html_url"
        case updatedAt = "updated_at", pullRequest = "pull_request"
    }

    public var isPull: Bool { pullRequest != nil }
}

public struct Comment: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let body: String?
    public let user: Issue.User?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, body, user, createdAt = "created_at"
    }
}

public struct WorkflowRun: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String?
    public let displayTitle: String?
    public let status: String?
    public let conclusion: String?
    public let event: String?
    public let headBranch: String?
    public let htmlUrl: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case id, name, displayTitle = "display_title", status, conclusion, event
        case headBranch = "head_branch", htmlUrl = "html_url", createdAt = "created_at"
    }

    public var title: String { displayTitle ?? name ?? "" }
}

public struct Workflow: Decodable, Sendable, Hashable, Identifiable {
    public let id: Int
    public let name: String
    public let path: String
    public let state: String

    public var file: String { path.split(separator: "/").last.map(String.init) ?? path }
}

public struct Commit: Decodable, Sendable, Hashable, Identifiable {
    public struct Inner: Decodable, Sendable, Hashable {
        public struct Person: Decodable, Sendable, Hashable {
            public let name: String?
            public let date: String?
        }

        public let message: String
        public let author: Person?
    }

    public let sha: String
    public let commit: Inner
    public let htmlUrl: String?

    enum CodingKeys: String, CodingKey {
        case sha, commit, htmlUrl = "html_url"
    }

    public var id: String { sha }
    public var title: String { commit.message.components(separatedBy: "\n").first ?? "" }
}

/// Ce que le flux « device » de GitHub demande d'afficher à l'utilisateur.
public struct DeviceCode: Decodable, Sendable, Hashable {
    public let deviceCode: String
    public let userCode: String
    public let verificationUri: String
    public let interval: Int?
    public let expiresIn: Int?

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code", userCode = "user_code"
        case verificationUri = "verification_uri", interval, expiresIn = "expires_in"
    }
}

/// Un changement dans un commit à plusieurs fichiers.
public struct FileChange: Sendable, Hashable {
    public let path: String
    /// `nil` : le fichier est supprimé.
    public let content: String?

    public static func write(_ path: String, _ content: String) -> FileChange { FileChange(path: path, content: content) }
    public static func remove(_ path: String) -> FileChange { FileChange(path: path, content: nil) }
}
