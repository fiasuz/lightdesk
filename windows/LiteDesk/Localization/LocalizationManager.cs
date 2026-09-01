using System.Collections.Generic;
using System.ComponentModel;

namespace LiteDesk.Localization;

public enum AppLanguage
{
    Uz,
    Ru,
    En,
}

// Live-switchable UI strings for the Home and active-session screens.
// XAML binds through the indexer (`Path=[Some.Key]`) rather than one
// property per string — changing `Language` raises PropertyChanged with a
// null/empty property name, which WPF's binding engine treats as "every
// property (including the indexer) may have changed", so every bound
// TextBlock/Button refreshes immediately without per-key wiring.
// Session-only (not persisted) by design — keeping this simple avoids
// depending on a generated Properties.Settings class that can't be
// verified to build in this environment (see project README: WPF isn't
// compiled here).
public sealed class LocalizationManager : INotifyPropertyChanged
{
    public static readonly LocalizationManager Instance = new();

    public event PropertyChangedEventHandler? PropertyChanged;

    private AppLanguage _language = AppLanguage.En;

    public AppLanguage Language
    {
        get => _language;
        set
        {
            if (_language == value) return;
            _language = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(null));
        }
    }

    public string this[string key] =>
        Strings.TryGetValue(key, out Dictionary<AppLanguage, string>? byLanguage) &&
        byLanguage.TryGetValue(_language, out string? value)
            ? value
            : key;

    private static readonly Dictionary<string, Dictionary<AppLanguage, string>> Strings = new()
    {
        ["Home.Subtitle"] = new()
        {
            [AppLanguage.Uz] = "MASOFADAN BOSHQARISH",
            [AppLanguage.Ru] = "УДАЛЁННОЕ УПРАВЛЕНИЕ",
            [AppLanguage.En] = "REMOTE CONTROL",
        },
        ["Home.MyAddress.Title"] = new()
        {
            [AppLanguage.Uz] = "Mening manzilim",
            [AppLanguage.Ru] = "Мой адрес",
            [AppLanguage.En] = "My address",
        },
        ["Home.MyAddress.Subtitle"] = new()
        {
            [AppLanguage.Uz] = "Shu manzilni yuborsangiz, sizga ulanadilar",
            [AppLanguage.Ru] = "Отправьте этот адрес, чтобы к вам подключились",
            [AppLanguage.En] = "Send this address so others can connect to you",
        },
        ["Home.MyAddress.Label"] = new()
        {
            [AppLanguage.Uz] = "Ulanish manzili",
            [AppLanguage.Ru] = "Адрес подключения",
            [AppLanguage.En] = "Connection address",
        },
        ["Home.MyAddress.Opening"] = new()
        {
            [AppLanguage.Uz] = "Ochilmoqda...",
            [AppLanguage.Ru] = "Открывается...",
            [AppLanguage.En] = "Opening...",
        },
        ["Home.MyAddress.Copy"] = new()
        {
            [AppLanguage.Uz] = "Nusxa olish",
            [AppLanguage.Ru] = "Копировать",
            [AppLanguage.En] = "Copy",
        },
        ["Home.MyAddress.Share"] = new()
        {
            [AppLanguage.Uz] = "Ulashish",
            [AppLanguage.Ru] = "Поделиться",
            [AppLanguage.En] = "Share",
        },
        ["Home.MyAddress.NewAddress"] = new()
        {
            [AppLanguage.Uz] = "Yangi manzil",
            [AppLanguage.Ru] = "Новый адрес",
            [AppLanguage.En] = "New address",
        },
        ["Home.MyAddress.Connected"] = new()
        {
            [AppLanguage.Uz] = "Ulandi — masofaviy foydalanuvchi sichqonchani boshqarmoqda",
            [AppLanguage.Ru] = "Подключено — удалённый пользователь управляет мышью",
            [AppLanguage.En] = "Connected — the remote user is controlling the mouse",
        },
        ["Home.MyAddress.Waiting"] = new()
        {
            [AppLanguage.Uz] = "Ulanish kutilmoqda...",
            [AppLanguage.Ru] = "Ожидание подключения...",
            [AppLanguage.En] = "Waiting for a connection...",
        },
        ["Home.Connect.Title"] = new()
        {
            [AppLanguage.Uz] = "Boshqa kompyuterga ulanish",
            [AppLanguage.Ru] = "Подключиться к другому компьютеру",
            [AppLanguage.En] = "Connect to another computer",
        },
        ["Home.Connect.Subtitle"] = new()
        {
            [AppLanguage.Uz] = "Sizga yuborilgan manzilni qo'ying",
            [AppLanguage.Ru] = "Введите отправленный вам адрес",
            [AppLanguage.En] = "Enter the address that was sent to you",
        },
        ["Home.Connect.Label"] = new()
        {
            [AppLanguage.Uz] = "Ulanish manzili",
            [AppLanguage.Ru] = "Адрес подключения",
            [AppLanguage.En] = "Connection address",
        },
        ["Home.Connect.Button"] = new()
        {
            [AppLanguage.Uz] = "ULANISH",
            [AppLanguage.Ru] = "ПОДКЛЮЧИТЬСЯ",
            [AppLanguage.En] = "CONNECT",
        },
        ["Home.Connect.Connecting"] = new()
        {
            [AppLanguage.Uz] = "ULANMOQDA...",
            [AppLanguage.Ru] = "ПОДКЛЮЧЕНИЕ...",
            [AppLanguage.En] = "CONNECTING...",
        },
        ["Home.Connect.Disclaimer"] = new()
        {
            [AppLanguage.Uz] = "Ulanish shifrlangan. Qarshi tomon so'rovni tasdiqlagach ekran ochiladi.",
            [AppLanguage.Ru] = "Соединение зашифровано. Экран откроется после подтверждения с другой стороны.",
            [AppLanguage.En] = "The connection is encrypted. The screen opens once the other side confirms.",
        },
        ["Home.Connect.InvalidCode"] = new()
        {
            [AppLanguage.Uz] = "Kodni tekshiring — to'liq ulanish kodini kiriting",
            [AppLanguage.Ru] = "Проверьте код — введите полный код подключения",
            [AppLanguage.En] = "Check the code — enter the full connection code",
        },
        ["Common.Granted"] = new()
        {
            [AppLanguage.Uz] = "Berilgan",
            [AppLanguage.Ru] = "Выдано",
            [AppLanguage.En] = "Granted",
        },
        ["Common.Ping"] = new()
        {
            [AppLanguage.Uz] = "Ping",
            [AppLanguage.Ru] = "Пинг",
            [AppLanguage.En] = "Ping",
        },
        ["Common.Fps"] = new()
        {
            [AppLanguage.Uz] = "FPS",
            [AppLanguage.Ru] = "FPS",
            [AppLanguage.En] = "FPS",
        },
        ["Common.Time"] = new()
        {
            [AppLanguage.Uz] = "Vaqt",
            [AppLanguage.Ru] = "Время",
            [AppLanguage.En] = "Time",
        },
        ["Common.Error"] = new()
        {
            [AppLanguage.Uz] = "Xato",
            [AppLanguage.Ru] = "Ошибка",
            [AppLanguage.En] = "Error",
        },
        ["Session.ConnectedTo"] = new()
        {
            [AppLanguage.Uz] = "{0} bilan ulanildi",
            [AppLanguage.Ru] = "Подключено к {0}",
            [AppLanguage.En] = "Connected to {0}",
        },
        ["Session.Disconnect"] = new()
        {
            [AppLanguage.Uz] = "UZISH",
            [AppLanguage.Ru] = "ОТКЛЮЧИТЬ",
            [AppLanguage.En] = "DISCONNECT",
        },
        ["Session.Disconnected"] = new()
        {
            [AppLanguage.Uz] = "Ulanish uzildi",
            [AppLanguage.Ru] = "Соединение разорвано",
            [AppLanguage.En] = "Disconnected",
        },
        ["ConnectionRequest.Title"] = new()
        {
            [AppLanguage.Uz] = "Ulanish so'rovi",
            [AppLanguage.Ru] = "Запрос на подключение",
            [AppLanguage.En] = "Connection request",
        },
        ["ConnectionRequest.Message"] = new()
        {
            [AppLanguage.Uz] = "Kimdir sizga ulanishni so'ramoqda. Ruxsat berasizmi?",
            [AppLanguage.Ru] = "Кто-то запрашивает подключение к вам. Разрешить?",
            [AppLanguage.En] = "Someone is requesting to connect to you. Allow it?",
        },
        ["ConnectionRequest.From"] = new()
        {
            [AppLanguage.Uz] = "Manba",
            [AppLanguage.Ru] = "Источник",
            [AppLanguage.En] = "From",
        },
        ["ConnectionRequest.Approve"] = new()
        {
            [AppLanguage.Uz] = "Ruxsat berish",
            [AppLanguage.Ru] = "Разрешить",
            [AppLanguage.En] = "Allow",
        },
        ["ConnectionRequest.Decline"] = new()
        {
            [AppLanguage.Uz] = "Rad etish",
            [AppLanguage.Ru] = "Отклонить",
            [AppLanguage.En] = "Decline",
        },
    };
}
