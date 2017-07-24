module __flow.channel;

import __flow.hull;
import flow.base.data;

package struct InChannel {
    string signal;
    TickInfo tick;
}

final class OutChannel {
    package Hull hull;

    bool send(Signal s) {
        return hull.send(s);
    }
}