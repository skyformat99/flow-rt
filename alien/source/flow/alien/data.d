module flow.alien.data;

import std.uuid;

import flow.blocks, flow.data;

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