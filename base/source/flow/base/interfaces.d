module flow.base.interfaces;

import std.uuid;

interface ITyped
{
    @property string type();
    @property void type(string);
}

interface IStealth{}

interface IIdentified
{
    @property UUID id();
}

interface IGrouped
{
    @property UUID group();
}