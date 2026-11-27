import Sharing

extension SharedKey where Self == AppStorageKey<String?> {
    public static var savedHost: Self {
        .appStorage("savedHost")
    }
}

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    public static var enhanceImage: Self {
        Self[.appStorage("enhanceImage"), default: false]
    }

    public static var timestampOverlay: Self {
        Self[.appStorage("timestampOverlay"), default: true]
    }
}
