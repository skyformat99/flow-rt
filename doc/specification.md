# Specification

To understand the specification a shift away from the usual perspective is necessary. Therefor you should first read the [Philosophic manifest](https://github.com/RalphBariz/flow/blob/master/doc/philosophy.md).

## Swarm
A set of functional entities running on one or many connected devices represents a **swarm**. Its composition can be automatically determined by a broadcasting system or, if broadcasting is not an option (internet, different subnets or a network hosting multiple swarms), by a listing service. As an alternative its composition can be explicitly defined by [entity](#Entity) configurations what makes sense for achieving a specific predefined solution.

![](https://github.com/RalphBariz/flow/raw/master/doc/image/spec/swarm.png)

## Device
A **device** is a physical unit connected to a communication network or hosts a signle device swarm. 

## Domain
A **domain** is a logic category of data, signals, entities and other. A domain is required for adressing objectes of the same type acting in different domains.

Example: The public transport(service) and their timetables(data objects) from different cities(domains).
You can search for public transport organizations of a cretain city or maybe for their timetables.

It is build of strings separated by '.'.
When addressing domains (harvesting data objects, etc.) it is possible to use regex matches in form of "foo./b.*r[0-9]/.subfoo".
Also simply not passing sublevels will return the whole domain(example: existing domains "foo.bar.one" and "foo.bar.two" are accumulated by passing "foo.bar" or for easier machine generation "foo.bar.").

A more complex example may be:
* Existing: "foo.123.bar.one.bla", "foo.123.bar.two.bla", "foo.223.bar.one.bla", "foo.224.bar.two.bla", "foo.223.bar.two.bli".
* Search pattern: "foo./[0-9]23/.bar..bla".
* Results: everything from "foo.123.bar.one.bla", "foo.123.bar.two.bla", "foo.223.bar.one.bla".
* Explaination: as you can see "foo.224.bar.two.bla" is not matching "/[0-9]23/" and "foo.223.bar.two.bli" is not matching "bla"

## Entity
An **entity** is a functional entity. A process on a device can host one or more entities.
Each entity has to be control and if necessary persistable by its entity manager.

![](https://github.com/RalphBariz/flow/raw/master/doc/image/spec/entity.png)

There can be entities one or more but not exclusively of following natures. This has te be seen more as an ideology.
* **Systemic entity**: It provides functionality necessary for a swarm beein able to function in a cretain environment.
* **Observing entity**: It reacts on specific undirected signals/data from the swarm but also interrupts of the hardware.
* **Servicing entity**: It serves the environment by listening to directed signals/data and generates directed signals/data.
* **Interfacing entity**: An interfacing entity provides an interface to others outside the swarm.

There are a few(one at the moment) predefined systemic entities:
* **Listing service**: provides as the name says a listing service, so other entities can find each other in a communication network not supporting broadcasting.

Each entity has a domain.

### Scope
Each entity has a scope:
* **Process**: the data object is only available to the process hosting the entity it was created in.
* **Device**: the data object can be synchronized to all data bags hosted on the device they are created/loaded.
* **Global**: the data object can be synchronized to all data bags hosted in the swarm.

### Resource
A device consists of different well defined **resources** having a (measur- and countable) value and a load. They are shared between local entities and always inform the whole swarm about their  value and load.
To acheive a good load balancing directed signals contain a list of the resource requirements an instance uses, so it can estimate which of the in this aspect equal entities of the swarm it should best signal.

### Listener
A listener waits for data/signals and triggers functionality. Its kind of the ear of an entity.

### Tasking
At developing software, we are common to code a functional flow executing code from across a hierarchy of functions and objects to acomplish tasks.
Honestly I think this kind of coding is overcomplicating things, inhibiting control and a stable functional flow.

Whereas the enities are supporting also classic implementation, I want to introduce an, at least for me, new way of thinking functionality.
Tasking entities provide the possibility of describing isolatable of functionality as tasks.
A task is started in a new thread and may lead to a following task running in the same thread.
Such a chain is called a **task chain**. It tries to provide a dynamic flow of logically delimited functionality.
From each task chain new chains may be forked.
The synchronization is happening via private signals and entity local variables.
All explicit faces are simply creating new task chains on beeing triggered.
This also allows temporary entities, since the controlling instance knows it may dispose an entity as soon as there is no active task
chain and also no explicit face.

### Signal
An event is a piece of slim data meant to inform listeners about everything happened. It has as all data objects a domain and a type. For signals there is a speacial domain meant for implementing watchdogs called "TRACE.". All entities should expose all internal signals required for controlling their functionality as TRACE signals. This allows the implementation of watchdogs for beeing able to guarantee the stability of essential parts of the swarm.

### Data bag
All data are created/loaded into a **data bag** which manages, synchronizes (depending on its availability) among the swarm and provides these data to its entity.

The best you could see data bags as short term memory. When your entity has to fulfill a certain task, the data bag is where all data required for processing that task is stored. As soon as that task is finished, the data bag has to be disposed. You may now think, "But what if I need a long term memory?" then you need to add a persisting data service to your swarm. Imagine a bunch of bugs crawiling around and a brain bug sitting somewhere overwatching everything, storing and recalling memories.

It is strongly adviced to split the data turnover of an entity among logical separated usages of data bags.

Data bags offer functionality to harvest data from the swarm using lazy loading and early disposing mechanisms. The disposing is managed by a usage rating algorithm which can be choosen/implemented as the requirements of the entity are proposing.

Example: The swarm hosts a data service backed by a RDBMS. Since this could contain huge amounts of data it is not adviced to physically hold all data which could be harvested at the same time in an entity. Due to data processing beeing sequential most of the time, data bags tend to load synchronized data on demand and realease data with a low usage rating or if memory gets low or exceeds a given limit(lowest rating dies). For sure disposing happens only after possible changes are synced into the swarm.

To achieve all the functionality in a safe way while beeing able to modify data, data bags offer a transaction mechanism locking the affected data objects swarm wide. Trying to modify data without initiating a transaction must lead into an exception. Commiting a transaction causes the data bag to notify all other data bags in the swarm about the changes so they can sync them. For beeing able to commit transaction in time before memory gets low but achieve the most performance, a data bag triggers signal handlers at crossing (default, configurable at instanciation) 10% marks of the available memory.

Data bags are disposed as soon as there are no active runtime code(in-process) subscribers any more.

#### Harvesting
**Data harvesting** searches depending on the aimed data scope for data of certain types and/or domains.

We have to differer between two main harvesting types:
* **Finite harvesting**: The harvesting task continues to execute until all available data in the aimed scope is harvested. This usecase is dedicated to logic requiring a snapshot of the available data (problem solving mechanisms).
* **Inifinite harvesting**: The harvesting task executes until it gets stopped by the subscriber of the harvest. This usecase is dedicated to logic requiring to get data as soon as it appears (trasnlation services translating one type of data into another).

Also we have to differ between:
* **Queued harvesting**: The subscriber of the harvest gets only one piece of data at a time as the name indicates in fifo order. As soon as the subscriber requests the next peice of data the already processed gets desynchronized(except it is marked as locked or part of a transaction) by the data bag.
* **Additive harvesting**: The data bag harvests into a collection of data the subscriber has to manually initiate desynchronization by removing it from the list. It is not allowed to add data to that list and will cause an exception.

Due to harvesting may take a longer time, harvesting returns a task filled asynchronous so the data may be already processed while the data bag is still executing that harvesting task.

#### Data object
FLOW offers **data object**s identified by an uuid generated at instanciation or set at loading them. Data objects always belongs to a domain. A data object has an **availability scope** which can be:
* **Entity**: the data object is only available to the entity it was created in.
* **Process**: the data object is only available to the process hosting the entity it was created in.
* **Device**: the data object can be synchronized to all data bags hosted on the device they are created/loaded.
* **Global**: the data object can be synchronized to all data bags hosted in the swarm.
* **Service**: the data object is global available and can be processed by any data service in the whole swarm.

Independent of the availability of a data object it gets synced to the partners data bag conserving the availability when actively transmitted over a communication channel.
Data objects are not synchronized between data bags for fun but on demand (explicit request by a subscriber of the affected data bag).
Data object are desynchronized by a data bag as soons as they are not marked as locked and no part of a harvest or transaction.
Data objects are deleted from the swarm as soon as there is no data bag managing them any more and no data service persisting them.

Continue to [Implementation guide](https://github.com/RalphBariz/flow/blob/master/doc/implementation.md)
