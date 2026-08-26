import Foundation
import MinoDomain

public enum LocalProfilePreferences {
    public static func load(
        for profile: ClientRuntimeProfile,
        userDefaults: UserDefaults = .standard
    ) -> CurrentProfile? {
        guard let data = userDefaults.data(forKey: key(for: profile)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CurrentProfile.self, from: data)
    }

    public static func save(
        _ value: CurrentProfile,
        for profile: ClientRuntimeProfile,
        userDefaults: UserDefaults = .standard
    ) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        userDefaults.set(try encoder.encode(value), forKey: key(for: profile))
    }

    private static func key(for profile: ClientRuntimeProfile) -> String {
        "Mino.profile.\(profile.id)"
    }
}
