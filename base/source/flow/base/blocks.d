module flow.base.blocks;

import std.traits, std.uuid, std.datetime, std.range.primitives;

static import flow.flow.type;
import flow.flow.tick, flow.flow.data, flow.flow.entity, flow.flow.signal;
import flow.base.interfaces;

// maybe an idea
// https://github.com/CyberShadow/ae/blob/master/utils/meta/args.d
// http://arsdnet.net/dcode/have_i_lost_my_marbles.d

// templates for data generation
/// generates a strong typed field into a data object
alias data = TData;
alias field = TField;
alias list = TList;

static import flow.flow.data;
alias Data = flow.flow.data.Data;

import flow.base.interfaces;
alias Data = flow.base.interfaces.Data;

static import flow.flow.signal;
alias Multicast = flow.flow.signal.Multicast;
alias Unicast = flow.flow.signal.Unicast;
alias Anycast = flow.flow.signal.Anycast;
alias signal = TSignal;

static import flow.flow.tick;
alias Tick = flow.flow.tick.Tick;
alias tick = TTick;

// templates for entity generation
/// generates a listener for an entity handling a signal
static import flow.flow.entity;
alias Entity = flow.flow.entity.Entity;
alias entity = TEntity;
alias listen = TListen;

static import flow.flow.process;
alias Flow = flow.flow.process.Flow;

/// check if two identifyables share their identity
bool identWith(IIdentified id1, IIdentified id2)
{
    auto t1 = id1.id;
    auto t2 = id2.id;
    return id1.id == id2.id;
}

alias fqn = flow.flow.type.fqn;
alias fqnOf = flow.flow.type.fqnOf;
alias as = flow.flow.type.as;
alias hasDefaultConstructor = flow.flow.type.hasDefaultConstructor;