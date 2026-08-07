public enum ProviderVisuals {
    public static func accentHex(for providerId: String) -> UInt32 {
        switch providerId.lowercased() {
        case "codex": 0x3DDC97
        case "claude": 0xF4A261
        case "gemini": 0x6FA8FF
        case "cursor": 0xD8D8DC
        default: 0x8B7CFF
        }
    }
}
