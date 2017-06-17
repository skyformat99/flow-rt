module flow.base.interfaces;

interface ITyped
{
    @property string type();
    @property void type(string);
}

interface IStealth{}

interface IQuiet{}

interface ISync{}

interface IIdentified
{
    @property string id();
}

interface IGrouped
{
    @property string group();
}