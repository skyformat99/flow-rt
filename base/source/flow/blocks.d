module flow.blocks;

import std.traits, std.uuid, std.datetime, std.range.primitives;

static import flow.base.type;
import flow.base.tick, flow.base.data, flow.base.organ, flow.base.entity, flow.base.signal;
import flow.interfaces;

// maybe an idea
// https://github.com/CyberShadow/ae/blob/master/utils/meta/args.d
// http://arsdnet.net/dcode/have_i_lost_my_marbles.d

// templates for data generation
/// generates a strong typed field into a data object
alias data = TData;
alias field = TField;
alias list = TList;

static import flow.base.data;
alias Data = flow.base.data.Data;

import flow.interfaces;
alias IData = flow.interfaces.IData;

static import flow.base.signal;
alias Multicast = flow.base.signal.Multicast;
alias Unicast = flow.base.signal.Unicast;
alias Anycast = flow.base.signal.Anycast;
alias signal = TSignal;

static import flow.base.tick;
alias Tick = flow.base.tick.Tick;
alias tick = TTick;

// templates for entity generation
/// generates a listener for an entity handling a signal
static import flow.base.entity;
alias Entity = flow.base.entity.Entity;
alias entity = TEntity;
alias listen = TListen;

/// generates an organ
static import flow.base.organ;
alias Organ = flow.base.organ.Organ;
alias organ = TOrgan;

static import flow.base.process;
alias Flow = flow.base.process.Flow;

/// check if two identifyables share their identity
bool identWith(IIdentified id1, IIdentified id2)
{
    auto t1 = id1.id;
    auto t2 = id2.id;
    return id1.id == id2.id;
}

alias fqn = flow.base.type.fqn;
alias fqnOf = flow.base.type.fqnOf;
alias as = flow.base.type.as;
alias hasDefaultConstructor = flow.base.type.hasDefaultConstructor;