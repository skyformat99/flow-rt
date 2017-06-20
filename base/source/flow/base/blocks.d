module flow.base.blocks;

import std.traits, std.uuid, std.datetime, std.range.primitives;

static import __flow.type;
import __flow.tick, __flow.data, __flow.entity, __flow.signal;
import flow.base.interfaces;

// maybe an idea
// https://github.com/CyberShadow/ae/blob/master/utils/meta/args.d
// http://arsdnet.net/dcode/have_i_lost_my_marbles.d

// templates for data generation
/// generates a strong typed field into a data object
alias data = TData;
alias field = TField;
alias list = TList;

static import __flow.data;
alias Data = __flow.data.Data;

static import __flow.signal;
alias Multicast = __flow.signal.Multicast;
alias Unicast = __flow.signal.Unicast;
alias Anycast = __flow.signal.Anycast;
alias signal = TSignal;

static import __flow.tick;
alias Tick = __flow.tick.Tick;
alias tick = TTick;

// templates for entity generation
/// generates a listener for an entity handling a signal
static import __flow.entity;
alias Entity = __flow.entity.Entity;
alias entity = TEntity;
alias listen = TListen;

static import __flow.process;
alias Flow = __flow.process.Flow;

/// check if two identifyables share their identity
bool identWith(IIdentified id1, IIdentified id2)
{
    auto t1 = id1.id;
    auto t2 = id2.id;
    return id1.id == id2.id;
}

alias fqn = __flow.type.fqn;
alias fqnOf = __flow.type.fqnOf;
alias as = __flow.type.as;
alias hasDefaultConstructor = __flow.type.hasDefaultConstructor;