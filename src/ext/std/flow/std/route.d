module flow.std.route;

private import flow.core;

/// transports a previous signal
class RoutedSignal : Unicast {
    private import flow.core.data : data, field;
    
    mixin data;

    mixin field!(Signal, "signal");
}