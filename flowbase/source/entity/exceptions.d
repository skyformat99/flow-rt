module flowbase.entity.exceptions;

import std.format;

class StateRestoreError : Error
{
    private string _entityId;
    @property string entityId(){return this._entityId;}

    private string _json;
    @property string json(){return this._json;}

    private byte[] _binary;
    @property byte[] binary(){return this._binary;}

    this(string entityId, string json)
    {
        this._entityId = entityId;
        this._json = json;
        super("state of \"" ~ entityId ~ "\" could not be restored");
    }

    this(string entityId, byte[] binary)
    {
        this._entityId = entityId;
        this._binary = binary;
        super("state of \"" ~ entityId ~ "\" could not be restored");
    }
}