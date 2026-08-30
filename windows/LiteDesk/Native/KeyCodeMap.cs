namespace LiteDesk.Native;

// Translates between Win32 virtual-key codes (winuser.h VK_* constants) and
// the layout-independent DOM `KeyboardEvent.code` strings used on the wire
// (see Protocol/WireMessages.cs). The same code string space is shared with
// the macOS app's KeyCodeMap.swift, so either side can send a code the other
// side has never seen a native keycode for.
internal static class KeyCodeMap
{
    internal static string? DomCode(int virtualKey)
    {
        return VkToDomCode.TryGetValue(virtualKey, out string? code) ? code : null;
    }

    internal static ushort? VirtualKey(string code)
    {
        return DomCodeToVk.TryGetValue(code, out ushort vk) ? vk : null;
    }

    private static readonly Dictionary<int, string> VkToDomCode = new()
    {
        [0x41] = "KeyA", [0x42] = "KeyB", [0x43] = "KeyC", [0x44] = "KeyD", [0x45] = "KeyE",
        [0x46] = "KeyF", [0x47] = "KeyG", [0x48] = "KeyH", [0x49] = "KeyI", [0x4A] = "KeyJ",
        [0x4B] = "KeyK", [0x4C] = "KeyL", [0x4D] = "KeyM", [0x4E] = "KeyN", [0x4F] = "KeyO",
        [0x50] = "KeyP", [0x51] = "KeyQ", [0x52] = "KeyR", [0x53] = "KeyS", [0x54] = "KeyT",
        [0x55] = "KeyU", [0x56] = "KeyV", [0x57] = "KeyW", [0x58] = "KeyX", [0x59] = "KeyY",
        [0x5A] = "KeyZ",

        [0x30] = "Digit0", [0x31] = "Digit1", [0x32] = "Digit2", [0x33] = "Digit3", [0x34] = "Digit4",
        [0x35] = "Digit5", [0x36] = "Digit6", [0x37] = "Digit7", [0x38] = "Digit8", [0x39] = "Digit9",

        [0x70] = "F1", [0x71] = "F2", [0x72] = "F3", [0x73] = "F4", [0x74] = "F5", [0x75] = "F6",
        [0x76] = "F7", [0x77] = "F8", [0x78] = "F9", [0x79] = "F10", [0x7A] = "F11", [0x7B] = "F12",

        [0x0D] = "Enter", [0x09] = "Tab", [0x20] = "Space", [0x1B] = "Escape", [0x08] = "Backspace",
        [0x2E] = "Delete", [0x2D] = "Insert", [0x24] = "Home", [0x23] = "End",
        [0x21] = "PageUp", [0x22] = "PageDown",
        [0x25] = "ArrowLeft", [0x26] = "ArrowUp", [0x27] = "ArrowRight", [0x28] = "ArrowDown",
        [0x14] = "CapsLock", [0x90] = "NumLock", [0x91] = "ScrollLock",

        [0xA0] = "ShiftLeft", [0xA1] = "ShiftRight",
        [0xA2] = "ControlLeft", [0xA3] = "ControlRight",
        [0xA4] = "AltLeft", [0xA5] = "AltRight",
        [0x5B] = "MetaLeft", [0x5C] = "MetaRight",

        [0xBD] = "Minus", [0xBB] = "Equal", [0xDB] = "BracketLeft", [0xDD] = "BracketRight",
        [0xDC] = "Backslash", [0xBA] = "Semicolon", [0xDE] = "Quote",
        [0xBC] = "Comma", [0xBE] = "Period", [0xBF] = "Slash", [0xC0] = "Backquote",

        [0x60] = "Numpad0", [0x61] = "Numpad1", [0x62] = "Numpad2", [0x63] = "Numpad3",
        [0x64] = "Numpad4", [0x65] = "Numpad5", [0x66] = "Numpad6", [0x67] = "Numpad7",
        [0x68] = "Numpad8", [0x69] = "Numpad9",
        [0x6A] = "NumpadMultiply", [0x6B] = "NumpadAdd", [0x6D] = "NumpadSubtract",
        [0x6E] = "NumpadDecimal", [0x6F] = "NumpadDivide",
    };

    private static readonly Dictionary<string, ushort> DomCodeToVk =
        VkToDomCode.ToDictionary(pair => pair.Value, pair => (ushort)pair.Key);
}
