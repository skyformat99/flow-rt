module flowbase.entity.signals;
import flowbase.entity.interfaces;

import flowbase.type.meta;

class SStateChanged
{
    mixin TSignal!(IEntity, EntityState, EntityState);
}