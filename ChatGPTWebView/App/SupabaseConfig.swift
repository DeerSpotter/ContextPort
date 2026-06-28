import Foundation

enum SupabaseConfig {
    static let projectURL = URL(string: "https://skejcbgrzlzgyjdjglrk.supabase.co")!

    // Publishable keys are intended for public clients such as mobile apps.
    // Do not replace this with a secret or service role key.
    static let publishableKey = "sb_publishable__0DZRvNOc0cZYJ0HvO50Qw_vxL9heac"

    static var memoryFunctionURL: URL {
        projectURL.appendingPathComponent("functions/v1/memory")
    }
}
