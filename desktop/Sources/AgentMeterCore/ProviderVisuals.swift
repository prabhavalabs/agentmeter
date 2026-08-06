public enum ProviderVisuals {
    public static func accentHex(for providerId: String) -> UInt32 {
        switch providerId.lowercased() {
        case "codex": 0x52E3B2
        case "claude": 0xF2A36B
        case "gemini": 0x5EC8FF
        case "cursor": 0xD6D5CC
        default: 0x8B7CFF
        }
    }
}
