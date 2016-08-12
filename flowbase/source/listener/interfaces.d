module flowbase.listener.interfaces;

import flowbase.entity.interfaces;
import flowbase.signal.interfaces;

interface IListener
{
    @property IEntity entity();
    @property string[] acceptedSignals();
    
    void run();
    void receive(IFlowSignal);
}