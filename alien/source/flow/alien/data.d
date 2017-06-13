module flow.alien.data;

import std.uuid;

import flow.base.blocks, flow.base.data;

class ComputingDevice : IdData
{
	mixin data;

    mixin field!(string, "name");
    mixin field!(string, "vendor");
}

class ComputingPlatform : IdData
{
	mixin data;
    mixin field!(string, "name");
    mixin field!(string, "vendor");
    mixin list!(ComputingDevice, "devices");
}