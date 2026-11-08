/// A controller in hand at the MacBook: Nightforge offers its full screen, once per start. It asks
/// rather than doing it: at a desk with a pad beside the keyboard, the window may be just right.
enum FullScreenOffer {
    static func offers(alreadyOffered: Bool, padConnected: Bool, inFront: Bool, fullScreen: Bool, onBuiltInScreen: Bool,
                       firstStart: Bool, gameOn: Bool, somethingOpen: Bool) -> Bool {
        !alreadyOffered && padConnected && inFront && !fullScreen && onBuiltInScreen && !firstStart && !gameOn && !somethingOpen
    }
}
