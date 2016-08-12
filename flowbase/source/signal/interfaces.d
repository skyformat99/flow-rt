module flowbase.signal.interfaces;

import flowbase.entity.interfaces;

interface IFlowSignal
{
    @property string id();
    @property string targetDomain();
    @property string dataDomain();
}

enum UnicastState
{
    Pending,
    Success,
    Fail
}

interface IUnicastSignal : IFlowSignal
{
    @property UnicastState state();
    @property IEntityRef acceptedBy();
    @property IResourceReq[] requirements();

    void connect(IEntityManager);

    bool accept(IEntityRef);
    void refuse(IEntityRef);
}

interface IBroadcastSignal : IFlowSignal
{
    void broadcast(IEntityManager);
}