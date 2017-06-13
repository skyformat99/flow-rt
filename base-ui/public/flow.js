define([
        "jquery",
        "backbone",
        "underscore",
        "vis",
        "slider",
        "text!flow.html"
    ], function($, Bb, _, Vis, Slider, tpl){

    var Flow = Flow || {};

    Flow.Validations = {
        stringNull: function(v, e, c) {
            if(v) {e.removeClass(c); return true;}
            else e.addClass(c); return false;;
        },
        idNull: function(v, e, c) {
            if(v && v !== "00000000-0000-0000-0000-000000000000") {e.removeClass(c); return true;}
            else e.addClass(c); return false;;
        },
    };

    Flow.Service = class Service {
        constructor() {
            this._running = false;
            this._listenings = [];
            this.entities = [];
            this._initHandler = [];
            this._entityAddedListeners = [];
            this._entityUpdatedListeners = [];
            this._entityRemovedListeners = [];
            this.traceNodes = new Vis.DataSet();
            this.traceEdges = new Vis.DataSet();
        }

        getSession() {
            var match = document.cookie.match(new RegExp("flowsession" + "=([^;]+)"));
            if (match) return match[1];
        }

        registerInit(callback) {
            if(this._initHandler.indexOf(callback) < 0)
                this._initHandler.push(callback);
        }

        _init() {
            if(!this._running && this.getSession())
            {
                this._running = true;

                Flow.loadJs("bootstrap");
                Flow.loadCss("bootstrap");

                Flow.host = new Flow.Host();
                Flow.tickManager = new Flow.TickManager();                
                Flow.tick = new Flow.Tick();
                Flow.tickManager.run(Flow.tick);

                this.beginListen("flow.base.signals.Pong", function(s) {
                    var flow = Flow;
                    var isIn = (s.source.id in Flow.service.entities);
                    if(!isIn)
                        Flow.service.entities[s.source.id] = new Bb.Model(s.data);
                    else
                        Flow.service.entities[s.source.id].set(s.data);

                    Flow.service.entities[s.source.id].id = s.source.id;
                    Flow.service.entities[s.source.id].__activePong = Date.now();
                    if(!isIn)
                        Flow.service.emitEntityAdded(Flow.service.entities[s.source.id]);
                    else
                        Flow.service.emitEntityUpdated(Flow.service.entities[s.source.id]);
                });
                this.addListenSource("flow.base.signals.Pong", "*");

                this.beginListen("flow.base.signals.TraceSend", function(s) {
                    console.log("flow.base.signals.TraceSend:" + JSON.stringify(s));

                    Flow.tick.trace.addOrUpdateNode(s.source.id, s.data, s.data.type, "dot", 0.5);
                });
                this.addListenSource("flow.base.signals.TraceSend", "*");

                this.beginListen("flow.base.signals.TraceReceive", function(s) {
                    console.log("flow.base.signals.TraceReceive:" + JSON.stringify(s));

                    Flow.tick.trace.addOrUpdateNode(s.source.id, s.data, s.data.type, "dot", 0.5);
                });
                this.addListenSource("flow.base.signals.TraceReceive", "*");

                this.beginListen("flow.base.signals.TraceBeginTick", function(s) {
                    console.log("flow.base.signals.TraceBeginTick:" + JSON.stringify(s));

                    Flow.tick.trace.addOrUpdateNode(s.source.id, s.data, Flow.tick.trace.renderTick(s.data), "box", 1);
                });
                this.addListenSource("flow.base.signals.TraceBeginTick", "*");

                this.beginListen("flow.base.signals.TraceEndTick", function(s) {
                    console.log("flow.base.signals.TraceEndTick:" + JSON.stringify(s));
                    
                    Flow.tick.trace.addOrUpdateNode(s.source.id, s.data, Flow.tick.trace.renderTick(s.data), "box", 1);
                });
                this.addListenSource("flow.base.signals.TraceEndTick", "*");

                for(var i in this._initHandler)
                    this._initHandler[i]();

                Flow.service._refresh();
                Flow.service._receive();

                setInterval(function() {
                    if(Flow.service._running) {
                        // receive outstanding signals
                        Flow.service._receive();
                    }
                }, 500);

                setInterval(function() {
                    if(Flow.service._running) {
                        Flow.service._refresh();
                    }
                }, 2000);
            }
        }

        _refresh() {
            var toDel = [];

            for(var i in Flow.service.entities) {                            
                var time = Flow.service.entities[i].__activePong;
                var cmp = Date.now();
                if(Flow.service.entities[i].__activePong + 6000 < Date.now())
                    toDel.push(i);
            }

            for(i in toDel.reverse()) {
                Flow.service.emitEntityRemoved(Flow.service.entities[toDel[i]]);
                delete Flow.service.entities[toDel[i]];
                Flow.service.entities.splice(i, 1);
            }

            var s = {dataType: "flow.base.signals.Ping"};
            Flow.service.send(s);
        }

        _receive() {
            var t = this;
            $.post("::flow::receive")
                .done(function(r) {
                    var data = JSON.parse(r);
                    if (data) {
                        for(var i in data) {
                            var f = t._listenings[data[i].type];
                            f(data[i]);
                        }
                    }
                });
        }

        start() {
            var t = this;
            $.post("::flow::validateSession")
                .done(function(r) {
                    if(!t.getSession()) {
                        $.post("::flow::requestSession")
                            .done(function(r){
                                if (r == "true") {
                                    t._init()
                                } else {
                                    alert("could not initialize flow session");
                                }
                            });
                    } else t._init();
                });
        }

        beginListen(signal, f) {
            if(!(signal in this._listenings)) {
                this._listenings[signal] = f;
            }
        }
        
        endListen(signal) {
            if(signal in this._listenings) {
                delete this._listenings[signal];
            }
        }

        addListenSource(signal, source) {
            if(signal in this._listenings) {
                $.post("::flow::addListenSource", signal+";"+source)
                    .done(function(r) {
                        if(!r) alert("could not add listen source \""+signal+"\"");
                    });
            }
        }

        removeListenSource(signal, source) {
            if(signal in this._listenings) {
                $.post("::flow::removeListenSource", signal+";"+source)
                    .done(function(r) {
                        if(!r) alert("could not remove listen source \""+signal+"\"");
                    });
            }
        }

        addEntityAddedListener(callback) {
            if(this._entityAddedListeners.indexOf(callback) < 0)
                this._entityAddedListeners.push(callback);
        }

        removeEntityAddedListener(callback) {
            var i = this._entityAddedListeners.indexOf(callback);
            if(i > -1)
                this._entityAddedListeners.splice(i, 1);
        }

        emitEntityAdded(entity) {
            for(var i in this._entityAddedListeners)
                this._entityAddedListeners[i](entity);
        }

        addEntityUpdatedListener(callback) {
            if(this._entityUpdatedListeners.indexOf(callback) < 0)
                this._entityUpdatedListeners.push(callback);
        }

        removeEntityUpdatedListener(callback) {
            var i = this._entityUpdatedListeners.indexOf(callback);
            if(i > -1)
                this._entityUpdatedListeners.splice(i, 1);
        }

        emitEntityUpdated(entity) {
            for(var i in this._entityUpdatedListeners)
                this._entityUpdatedListeners[i](entity);
        }

        addEntityRemovedListener(callback) {
            if(this._entityRemovedListeners.indexOf(callback) < 0)
                this._entityRemovedListeners.push(callback);
        }

        removeEntityRemovedListener(callback) {
            var i = this._entityRemovedListeners.indexOf(callback);
            if(i > -1)
                this._entityRemovedListeners.splice(i, 1);
        }

        emitEntityRemoved(entity) {
            for(var i in this._entityRemovedListeners)
                this._entityRemovedListeners[i](entity);
        }

        send(s, e) {
            if(e) {
                if(e.attributes)
                {
                    if(e.attributes.reference)
                        s.destination = e.attributes.reference;
                    else
                        s.destination = e.attributes;
                }
                else
                    s.destination = e;
            }

            s.id = s.id || Flow.randomId();
            $.post("::flow::send", JSON.stringify(s))
                .always(function(r){
                    if(!eval(r)) {
                        var m = "could not send:\n"+JSON.stringify(s);
                        console.log(m);
                        alert(m);
                    }
                });
        }
    }

    Flow.Host = Bb.View.extend({
        el: "#host",
        template: _.template(_.unescape($(tpl).filter("#Flow-Host").html())),
        initialize: function() {
            this._active = null;
            this.dataEditorTypes = [];

            this.render();
        },
        destroy: function() {
            this.remove();
            this.unbind();
        },
        render: function() {
            this.$el.html(this.template);
            this.container = this.$("#Flow-Host-body");
            return this;
        },
        activate: function(tick) {
            if(this._active) this._active.$el.first().hide();
            this._active = tick;
            if(this._active) {
                this._active.$el.first().show();
            
                if(this._active.focus)
                    this._active.focus();
            }
        },
        registerDataEditor: function(dataType, viewType) {
            if(!(dataType in this.dataEditorTypes)) {
                this.dataEditorTypes[dataType] = viewType;
                return true;
            }
            else return false;
        },
    });

    Flow.Ticker = Bb.View.extend({
        tagName: "li",
        template: _.template(_.unescape($(tpl).filter("#Flow-Ticker").html())),
        events: {
            "click #btn": "activate",
            "click #btnClose": "close",
        },
        initialize: function(o) {
            this.next(o.init);
        },
        destroy: function() {
            this.remove();
            this.unbind();
        },
        render: function() {
            this.$el.html(this.template({display: this._active.getDisplay()}));

            if(this._active.closeAllowed == undefined || this._active.closeAllowed)
                this.$("#btnClose").show();
            else
                this.$("#btnClose").hide();

            return this;
        },
        activate: function() {
            if(!this.closed) {
                Flow.host.activate(this._active);
                Flow.tickManager.activate(this);
            }
        },
        send: function(s, e) {
            Flow.service.send(s, e);
        },
        answer: function(s) {
            Flow.service.send(s, this.trigger);
        },
        next: function(tick, data) {
            var allowed = this.checkDirty();
            if(allowed) {
                if(this._active)
                    delete this._active;

                if(this.trigger == null && tick.trigger != null) {
                    this.trigger = t.trigger;
                } else if(this.trigger != null) {
                    tick.trigger = this.trigger;
                }
                tick.data = data;
                tick.ticker = this;
                this._active = tick;
                this.render();

                Flow.host.container.append(this._active.$el);
            }
        },
        repeat: function() {
            this.next(this._active);
        },
        checkDirty: function() {
            return !this._active || !this._active.dirty || confirm("Are you sure you want to discard pending changes?");
        },
        close: function() {
            var allowed = this.checkDirty();
            if(allowed) {
                if(this._active) {
                    if(this._active.destroy)
                        this._active.destroy();
                    delete this._active;
                }
                this.closed = true;
                Flow.tickManager.removeTicker(this);
            }
        }
    });

    Flow.TickManager = Bb.View.extend({
        el: "#nav",
        template: _.template(_.unescape($(tpl).filter("#Flow-TickManager").html())),
        initialize: function(o) {
            this._ticker = [];
            this._active = null;
            this._last = null;

            this.render();
        },
        destroy: function() {
            this.remove();
            this.unbind();
            for(i in this._ticker)
                this._ticker[i].destroy();
        },
        render: function() {
            this.$el.html(this.template);
            this.container = this.$("#Flow-TickManager-body");
            return this;
        },
        run: function(tick) {
            tick.$el.first().hide();
            var ticker = new Flow.Ticker({init: tick});
            this.container.append(ticker.$el);
            this._ticker.push(ticker);
            ticker.activate();
        },
        activate: function(ticker) {
            for(i in this._ticker)
                this._ticker[i].$el.removeClass("active");
            this._active = ticker;
            this._active.$el.addClass("active");
        },
        removeTicker: function(ticker) {
            var i = this._ticker.indexOf(ticker);

            var isActive = this._active == ticker;

            if(i) {
                this._ticker.splice(i, 1);
                ticker.destroy();
                delete ticker;
            }
            
            if(isActive)
                this._ticker[0].activate();
        },
    });

    Flow.OverviewView = Bb.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-OverviewView").html())),
        initialize: function() {
            this.entityViewTypes = [];
            this.entityViews = [];
            Flow.service.addEntityAddedListener(this.addEntity);
            Flow.service.addEntityUpdatedListener(this.updateEntity);
            Flow.service.addEntityRemovedListener(this.removeEntity);
            this.render();
        },
        destroy: function() {
            this.remove();
            this.unbind();
            
            for(i in this.entityViews)
                this.entityViews[i].destroy();
        },
        render: function() {
            this.$el.html(this.template);
            this.container = this.$("#body");
            return this;
        },
        show: function() {
            this.$el.first().show();
        },
        hide: function() {
            this.$el.first().hide();
        },
        register: function(entityType, viewType) {
            if(!(entityType in this.entityViewTypes)) {
                this.entityViewTypes[entityType] = viewType;
                return true;
            }
            else return false;
        },
        addEntity: function(entity) {
            console.log("entity added " + entity.attributes.reference.type + "|" + entity.attributes.reference.id);

            var entityViewTypes = Flow.tick.overview.entityViewTypes;
            var entityViews = Flow.tick.overview.entityViews;
            var container = Flow.tick.overview.container;

            if(entity.attributes.reference.type in entityViewTypes && !(entity.id in entityViews)) {
                entityViews[entity.id] = new entityViewTypes[entity.attributes.reference.type](entity);
                entityViews[entity.id].$el.addClass("entityView");
                container.append(entityViews[entity.id].$el);
            }
        },
        updateEntity: function(entity) {
            console.log("entity updated " + entity.attributes.reference.type + "|" + entity.attributes.reference.id);

            var entityViews = Flow.tick.overview.entityViews;

            if(entity.id in entityViews && entityViews[entity.id].refresh)
                entityViews[entity.id].refresh(entity);
        },
        removeEntity: function(entity) {
            console.log("entity removed " + entity.get("type") + "|" + entity.id);

            var entityViewTypes = Flow.tick.overview.entityViewTypes;
            var entityViews = Flow.tick.overview.entityViews;
            var container = Flow.tick.overview.container;

            if(entity.id in entityViews) {
                entityViews[entity.id].destroy();
                delete entityViews[entity.id];
            }
        }
    });

    Flow.TraceViewModel = Bb.Model.extend({
        defaults: {
            act: 0,
            seq: 0
        }
    });

    Flow.TraceView = Bb.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-TraceView").html())),
        events: {
            "click #Flow-TraceView-btnClear": "clear",
        },
        initialize: function() {
            Flow.loadCss("slider");
            Flow.loadCss("vis");
            this.model = new Flow.TraceViewModel();
            this._boundModelChanged = _.bind(this.modelChanged, this);
            this.model.bind("change", this._boundModelChanged);
            this.render();
            this.clear();
        },
        destroy: function() {
            this.model.unbind("change", this._boundModelChanged);
            this.remove();
            this.unbind();
            this.model.unbind();
            this.network.destroy();

            //for(i in this.entityViews)
            //    this.entityViews[i].destroy();
        },
        modelChanged: function(m) {
            this.slider.setAttribute("max", m.attributes.seq);
            this.slider.setValue(m.attributes.act);
        },
        render: function() {
            this.$el.html(this.template(this.model.attributes));
            this.slider = new Slider(this.$("#Flow-TraceView-slider").get()[0]);
            this.slider.on("change", _.bind(this.changeAct, this));
            var container = this.$("#Flow-TraceView-body").get()[0];
            var data = {nodes: Flow.service.traceNodes, edges: Flow.service.traceEdges};
            this.network = new Vis.Network(container, data, {});

            return this;
        },
        refresh: function() {
            var ids = Flow.service.traceNodes.getIds();

            var updateArray = [];
            for(i in ids)
                updateArray.push({id: ids[i], hidden: i > this.model.attributes.act});
            Flow.service.traceNodes.update(updateArray);
        },
        changeAct: function(e) {
            this.model.set("act", e.newValue);

            this.refresh();
            this.network.redraw();
        },
        addOrUpdateNode: function(source, data, label, shape, mass) {
            var inEdgeId = data.trigger+"|"+data.id;
            var outEdgeId = source+"|"+data.id;
            var node = Flow.service.traceNodes.get(data.id);
            if(!node)
            {
                Flow.service.traceNodes.add({id: data.id, group: data.group, shape: shape, label: label, mass: mass, shadow: {enabled: true, color: "red"}});
                this.model.set("seq", this.model.attributes.seq + 1);
                if(this.model.attributes.act == this.model.attributes.seq - 1);
                    this.model.set("act", this.model.attributes.seq);
            }
            else
                Flow.service.traceNodes.update({id: data.id, mass: node.mass + mass, shadow: {enabled: false}});

            if(!Flow.service.traceEdges.get(inEdgeId))
                Flow.service.traceEdges.add({id: inEdgeId, from: data.trigger, to: data.id});

            if(!Flow.service.traceEdges.get(outEdgeId))
                Flow.service.traceEdges.add({id: outEdgeId, from: data.id, to: source});
        },
        renderTick: function(data) {
            var text = data.entityType+"\n"+data.tick;

            return text;
        },
        clear: function() {
            var me = Flow.service.traceNodes.get(Flow.service.getSession());
            Flow.service.traceNodes.clear();
            Flow.service.traceEdges.clear();
            Flow.service.traceNodes.add({id: Flow.service.getSession(), shape: "database", color: "white", label: "Session", mass: 3});
        },
        show: function() {
            this.$el.first().show();
        },
        hide: function() {
            this.$el.first().hide();
        }
    });

    Flow.Tick = Bb.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Tick").html())),
        events: {
            "click #Flow-Tick-btnOverview": "showOverview",
            "click #Flow-Tick-btnTrace": "showTrace"
        },
        destroy: function() {
            this.remove();
            this.unbind();
            //this.model.unbind("change", this.modelChanged);

            this.overview.destroy();
            this.trace.destroy();
        },
        initialize: function() {
            this.closeAllowed = false;
            this.render();
        },
        render: function() {
            this.$el.html(this.template);
            this.container = this.$("#Flow-Tick-body");
            this.overview = new Flow.OverviewView({});
            this.trace = new Flow.TraceView();
            this.container.append(this.overview.$el);
            this.container.append(this.trace.$el);
            this.showOverview();
            return this;
        },
        getDisplay: function() {
            var display = _.template(_.unescape($(tpl).filter("#Flow-Tick-display").html()))();
            return display;
        },
        showOverview: function() {
            $("#Flow-Tick-btnTrace").removeClass("active");
            this.trace.hide();
            $("#Flow-Tick-btnOverview").addClass("active");
            this.overview.show();
        },
        showTrace: function() {
            $("#Flow-Tick-btnOverview").removeClass("active");
            this.overview.hide();
            $("#Flow-Tick-btnTrace").addClass("active");
            this.trace.show();
        }
    });

    Flow.service = new Flow.Service();
    
    Flow.randomId = function(){
        var d = new Date().getTime();
        if(window.performance && typeof window.performance.now === "function"){
            d += performance.now(); //use high-precision timer if available
        }
        var uuid = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
            var r = (d + Math.random()*16)%16 | 0;
            d = Math.floor(d/16);
            return (c=='x' ? r : (r&0x3|0x8)).toString(16);
        });
        return uuid;
    };

    Flow.emptyId = function() {
        return "00000000-0000-0000-0000-000000000000";
    }

    Flow.loadCss = function(name) {
        var link = document.createElement("link");
        link.type = "text/css";
        link.rel = "stylesheet";
        link.href = "./"+name+".css";
        document.getElementsByTagName("head")[0].appendChild(link);
    }

    Flow.loadJs = function(name) {
        var script = document.createElement("script");
        script.type = "text/javascript";
        script.charset="utf-8";
        script.async = true;
        script.src = "./"+name+".js";
        document.getElementsByTagName("head")[0].appendChild(script);
    }

    return Flow;
});