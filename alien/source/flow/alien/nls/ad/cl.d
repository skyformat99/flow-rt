module flow.alien.nls.ad.cl;

import std.uuid;
import flow.blocks, flow.data;
import flow.util.memory;

// data
class Description : Data
{
    mixin data;

    mixin field!(string, "globalSrc");

    mixin list!(EntityDescription, "entities");
    mixin list!(ActDescription, "acts");
    mixin list!(MappingDescription, "mappings");
}

class EntityDescription : IdData
{
    mixin data;

    mixin field!(string, "name");
    
    mixin field!(ulong, "amount");
    mixin field!(string, "paramSrc");
}

class InformationDescription : IdData
{
    mixin data;

    mixin field!(string, "name");
    mixin field!(PropertyType, "type");
    mixin field!(uint[], "dimensions");
    mixin field!(bool, "isAbsolute");
}

class ActDescription : IdData
{
    mixin data;

    mixin field!(string, "name");
    mixin field!(bool, "measurement");
}

class XxActDescription : ActDescription
{
    mixin data;

    mixin list!(InformationDescription, "xInfos");

    mixin field!(string, "actSrc");
}

class XyActDescription : ActDescription
{
    mixin data;

    mixin list!(InformationDescription, "xInfos");
    mixin list!(InformationDescription, "yInfos");

    mixin field!(string, "actSrc");
    mixin field!(string, "joinSrc");
}

class MappingDescription : IdData
{
    mixin data;

    mixin field!(UUID, "act");
}

class XxMappingDescription : MappingDescription
{
    mixin data;

    mixin field!(UUID, "xEntity");
}

class XyMappingDescription : MappingDescription
{
    mixin data;

    mixin field!(UUID, "xEntity");
    mixin field!(UUID, "yEntity");
}

enum PropertyType
{
    Integer,
    Float
}

// contexts and settings
class Context : Data
{
	mixin data;

    mixin list!(UUID, "sessions");
}

class ClAdNls : Entity
{
    mixin entity!(Context);
}