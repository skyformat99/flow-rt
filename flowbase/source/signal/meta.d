module flowbase.signal.meta;

mixin template TFlowSignal()
{
    private string _id;
    @property string id(){return this._id;}

    private string _targetDomain;
    @property string targetDomain(){return this._targetDomain;}

    private string _dataDdomain;
    @property string dataDomain(){return this._dataDdomain;}
}