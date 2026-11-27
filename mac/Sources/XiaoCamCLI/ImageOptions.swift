import ArgumentParser

struct ImageOptions: ParsableArguments {
    @Flag(inversion: .prefixedNo, help: "Clean noise and sharpen. Default: the app setting.")
    var enhance: Bool?

    @Flag(inversion: .prefixedNo, help: "Put the date and time on the image. Default: the app setting.")
    var timestamp: Bool?
}
