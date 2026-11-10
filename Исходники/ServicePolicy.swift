import Foundation

enum MusicService {
    static let hosts: Set<String> = [
        "music.yandex.ru", "music.yandex.com", "music.yandex.by", "music.yandex.kz", "music.yandex.uz",
    ]
    static func allowsNavigation(_ url: URL, testing: Bool = false) -> Bool {
        url.scheme == "https" || (url.scheme == "about" && url.absoluteString == "about:blank")
            || (testing && url.isFileURL)
    }
    static func trackPageURL(_ raw: String) -> URL? {
        guard let url = URL(string: raw, relativeTo: URL(string: "https://music.yandex.ru"))?.absoluteURL,
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: true),
            parts.scheme == "https", let host = parts.host, hosts.contains(host),
            parts.user == nil, parts.password == nil, parts.port == nil || parts.port == 443
        else { return nil }
        let path = parts.path.split(separator: "/")
        let isTrack = path.count == 2 && path[0] == "track" && !path[1].isEmpty
        let isAlbumTrack =
            path.count == 4 && path[0] == "album" && path[2] == "track" && !path[1].isEmpty
            && !path[3].isEmpty
        guard isTrack || isAlbumTrack else { return nil }
        parts.query = nil
        parts.fragment = nil
        return parts.url
    }
    static func sanitizeHistory(_ history: [[String: Any]]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        for value in history.suffix(150) {
            let id = String((value["id"] as? String ?? "").prefix(128))
            let title = String((value["title"] as? String ?? "").prefix(1024))
            guard !id.isEmpty || !title.isEmpty else { continue }
            let duration = value["duration"] as? Double ?? 0
            let safeDuration: Double = duration.isFinite ? min(86400, max(0, duration)) : 0
            result.append([
                "id": id, "title": title,
                "artist": String((value["artist"] as? String ?? "").prefix(1024)),
                "url": trackPageURL(value["url"] as? String ?? "")?.absoluteString ?? "",
                "duration": safeDuration,
                "index": -1, "bucket": "history", "current": false, "source": "wave",
            ])
        }
        return result
    }

}
