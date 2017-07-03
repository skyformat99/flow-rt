module flow.base.blocks;

import std.traits, std.uuid, std.datetime, std.range.primitives;

import flow.base.interfaces, flow.base.data;

// maybe an idea
// https://github.com/CyberShadow/ae/blob/master/utils/meta/args.d
// http://arsdnet.net/dcode/have_i_lost_my_marbles.d

// templates for data generation
/// generates a strong typed field into a data object

static import __flow.data;
alias data = __flow.data.TData;
alias field = __flow.data.TField;
alias list = __flow.data.TList;
alias Data = __flow.data.Data;

static import __flow.signal;
alias signal = __flow.signal.TSignal;

static import __flow.ticker;
//alias Ticker = __flow.tick.Ticker;
alias Tick = __flow.ticker.Tick;
alias tick = __flow.ticker.TTick;

// templates for entity generation
/// generates a listener for an entity handling a signal
static import __flow.entity;
alias Entity = __flow.entity.Entity;
alias entity = __flow.entity.TEntity;
alias listen = __flow.entity.TListen;

static import __flow.process;
alias Flow = __flow.process.Flow;

/// check if two identifyables share their identity
bool identWith(IIdentified id1, IIdentified id2)
{
    return id1.id == id2.id;
}

/// check if two entities share their identity
bool identWith(EntityPtr e1, EntityPtr e2)
{
    return e1.id == e2.id && e1.domain == e2.domain;
}

static import __flow.type;
alias fqn = __flow.type.fqn;
alias fqnOf = __flow.type.fqnOf;
alias as = __flow.type.as;
alias hasDefaultConstructor = __flow.type.hasDefaultConstructor;