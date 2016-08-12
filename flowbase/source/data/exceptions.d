module flowbase.data.exceptions;

class DataReflectionError : Error
{
    this(string msg)
    {
        super(msg);
    }
}