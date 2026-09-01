import Foundation
import Combine

/// The three interface languages the home/active-session screens support,
/// switchable at runtime from the language picker (see the design's
/// language dropdown on screen "01 Ulanish").
enum AppLanguage: String, CaseIterable, Identifiable {
    case uz, ru, en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .uz: return "O'zbekcha"
        case .ru: return "Русский"
        case .en: return "English"
        }
    }

    var code: String {
        switch self {
        case .uz: return "UZ"
        case .ru: return "RU"
        case .en: return "EN"
        }
    }
}

final class LocalizationManager: ObservableObject {
    private static let defaultsKey = "litedesk.language"

    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: Self.defaultsKey) }
    }

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey), let saved = AppLanguage(rawValue: raw) {
            language = saved
        } else {
            language = .en
        }
    }

    func t(_ key: LocalizedKey) -> String {
        LocalizedStrings.table[key]?[language] ?? LocalizedStrings.table[key]?[.uz] ?? key.rawValue
    }
}

/// One case per user-facing string on the home and active-session screens.
enum LocalizedKey: String {
    case appTagline
    case myAddressTitle
    case myAddressSubtitle
    case connectionAddressLabel
    case copyButton
    case shareButton
    case newAddressButton
    case tunnelStarting
    case connectTitle
    case connectSubtitle
    case connectionCodeLabel
    case connectionCodePlaceholder
    case connectButton
    case connectingButton
    case connectHint
    case codeInvalidError
    case connectErrorPrefix
    case connectedBadge
    case pingLabel
    case fpsLabel
    case sessionEndButton
    case timeLabel
    case monitoringTitle
    case trafficLabel
}

enum LocalizedStrings {
    static let table: [LocalizedKey: [AppLanguage: String]] = [
        .appTagline: [
            .uz: "Internet orqali masofadan boshqarish",
            .ru: "Удалённое управление через интернет",
            .en: "Remote control over the internet",
        ],
        .myAddressTitle: [
            .uz: "Mening manzilim",
            .ru: "Мой адрес",
            .en: "My address",
        ],
        .myAddressSubtitle: [
            .uz: "Shu manzilni yuborsangiz, sizga ulanadilar",
            .ru: "Отправьте этот адрес — к вам подключатся",
            .en: "Send this address and others can connect to you",
        ],
        .connectionAddressLabel: [
            .uz: "Ulanish manzili",
            .ru: "Адрес подключения",
            .en: "Connection address",
        ],
        .copyButton: [
            .uz: "Nusxa olish",
            .ru: "Копировать",
            .en: "Copy",
        ],
        .shareButton: [
            .uz: "Ulashish",
            .ru: "Поделиться",
            .en: "Share",
        ],
        .newAddressButton: [
            .uz: "Yangi manzil",
            .ru: "Новый адрес",
            .en: "New address",
        ],
        .tunnelStarting: [
            .uz: "Manzil tayyorlanmoqda...",
            .ru: "Адрес подготавливается...",
            .en: "Preparing address...",
        ],
        .connectTitle: [
            .uz: "Boshqa kompyuterga ulanish",
            .ru: "Подключиться к другому компьютеру",
            .en: "Connect to another computer",
        ],
        .connectSubtitle: [
            .uz: "Sizga yuborilgan manzilni qo'ying",
            .ru: "Вставьте адрес, который вам отправили",
            .en: "Paste the address you were sent",
        ],
        .connectionCodeLabel: [
            .uz: "Ulanish manzili",
            .ru: "Адрес подключения",
            .en: "Connection address",
        ],
        .connectionCodePlaceholder: [
            .uz: "masalan: 123456-xxxx",
            .ru: "например: 123456-xxxx",
            .en: "e.g. 123456-xxxx",
        ],
        .connectButton: [
            .uz: "ULANISH",
            .ru: "ПОДКЛЮЧИТЬСЯ",
            .en: "CONNECT",
        ],
        .connectingButton: [
            .uz: "ULANMOQDA...",
            .ru: "ПОДКЛЮЧЕНИЕ...",
            .en: "CONNECTING...",
        ],
        .connectHint: [
            .uz: "Ulanish shifrlangan. Qarshi tomon so'rovni tasdiqlagach ekran ochiladi.",
            .ru: "Соединение зашифровано. Экран откроется после подтверждения запроса.",
            .en: "The connection is encrypted. The screen opens once the request is confirmed.",
        ],
        .codeInvalidError: [
            .uz: "Kodni tekshiring — to'liq ulanish kodini kiriting",
            .ru: "Проверьте код — введите полный код подключения",
            .en: "Check the code — enter the full connection code",
        ],
        .connectErrorPrefix: [
            .uz: "Xato: ",
            .ru: "Ошибка: ",
            .en: "Error: ",
        ],
        .connectedBadge: [
            .uz: "Ulandi",
            .ru: "Подключено",
            .en: "Connected",
        ],
        .pingLabel: [
            .uz: "Ping",
            .ru: "Пинг",
            .en: "Ping",
        ],
        .fpsLabel: [
            .uz: "FPS",
            .ru: "FPS",
            .en: "FPS",
        ],
        .sessionEndButton: [
            .uz: "Seansni tugatish",
            .ru: "Завершить сеанс",
            .en: "End session",
        ],
        .timeLabel: [
            .uz: "Vaqt",
            .ru: "Время",
            .en: "Time",
        ],
        .monitoringTitle: [
            .uz: "Kuzatuv",
            .ru: "Мониторинг",
            .en: "Monitoring",
        ],
        .trafficLabel: [
            .uz: "Trafik",
            .ru: "Трафик",
            .en: "Traffic",
        ],
    ]
}
