/// When macOS's question about notifications is put. Not when the first download ends, often with a
/// game in front and only a pad in hand, but once the first start is over, Nightforge is in front
/// and the mouse or trackpad was used last: then someone can answer it.
enum NotificationMoment {
    static func asksNow(alreadyAsked: Bool, setting: Bool, inFront: Bool, gameOn: Bool, firstStart: Bool, padUsedLast: Bool) -> Bool {
        !alreadyAsked && setting && inFront && !gameOn && !firstStart && !padUsedLast
    }
}
