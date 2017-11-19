module flow.std.route;

private static import flow.data.engine;
private static import flow.core.data;

class RoutedSignal : flow.core.data.Unicast {
    private import flow.core.data : Signal;

    mixin flow.data.engine.data;

    mixin flow.data.engine.field!(Signal, "signal");
}