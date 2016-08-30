define([
    "jquery",
    "flow",
    "backbone",
    "backbone.epoxy",
    "underscore",
    "vis",
    "ace/ace",
    "text!flow.alien.nls.ad.cl.html"
], function($, Flow, Bb, Ep, _, Vis, Ace, tpl) {

    var Flow = Flow || {};
    Flow.Alien = Flow.Alien || {};
    Flow.Alien.Nls = Flow.Alien.Nls || {};
    Flow.Alien.Nls.Ed = Flow.Alien.Nls.Ed || {};
    Flow.Alien.Nls.Ed.Cl = Flow.Alien.Nls.Ed.Cl || {};

    Flow.Alien.Nls.Ed.Cl.DescriptionEditView = Ep.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Alien-Nls-Ed-Cl-DescriptionEditView").html())),
        events: {
            "click #btnAddEntity": "addEntity",
            "click #btnAddXxAct": "addXxAct",
            "click #btnAddXxMapping": "addXxMapping",
            "click #btnAddXyAct": "addXyAct",
            "click #btnAddXyMapping": "addXyMapping",
            "click #btnDelete": "deleteSelected",
        },
        initialize: function(o) {
            this.model.owner = this;
            this._graphNodes = new Vis.DataSet();
            this._graphEdges = new Vis.DataSet();
            this._boundModelChanged = _.bind(this.modelChanged, this);
            this.model.bind("change", this._boundModelChanged);
            this.render();
        },
        modelChanged: function(m) {
            this.validate(true);
        },
        updateEntity: function(e) {
            var m = this.model.attributes;
            for (var i in m.entities)
                if (m.entities[i].id == e.id) {
                    m.entities[i] = e;
                    break;
                }
        },
        updateAct: function(e) {
            var m = this.model.attributes;
            for (var i in m.acts)
                if (m.acts[i].id == e.id) {
                    m.acts[i] = e;
                    break;
                }
        },
        updateMapping: function(e) {
            var m = this.model.attributes;
            for (var i in m.mappings)
                if (m.mappings[i].id == e.id) {
                    m.mappings[i] = e;
                    break;
                }
        },
        destroy: function() {
            this.destroyEditor();
            this.remove();
            this.unbind();
            this.model.unbind("change", this._boundModelChanged);
            this._network.destroy();
        },
        createSrcEditor: function(e, p, c) {
            var editor = Ace.edit(e);
            editor.owner = this;
            editor.property = p;
            editor.setOptions({ maxLines: 33 });
            editor.setTheme("ace/theme/iplastic");
            editor.setHighlightActiveLine(false);
            editor.getSession().setMode("ace/mode/c_cpp");
            editor.setValue(this.model.get(p));
            editor.getSession().on('change', c);

            return editor;
        },
        render: function() {
            if (this._network) this._network.destroy();
            this.prepareModel();
            this.$el.html(this.template(this.model));
            this.applyBindings();

            this._globalSrcEditor = this.createSrcEditor(
                this.$("#globalSrcEditor")[0], "globalSrc", _.bind(this.globalSrcChange, this)
            );

            this.container = this.$("#body");

            var data = {
                nodes: this._graphNodes,
                edges: this._graphEdges
            };
            this._network = new Vis.Network(this.$("#graph").get()[0], data, {});
            this._network.on("select", _.bind(this.networkSelected, this));
            this._network.on("dragEnd", _.bind(function(e) {
                if (this._editor)
                    this._network.selectNodes([this._editor.model.id]);
                else
                    this._network.unselectAll();
            }, this));

            this.updateVis();

            this._network.unselectAll();

            this.validate(true);

            return this;
        },
        updateVis: function() {
            for (var i in this.model.attributes.entities)
                this.addOrUpdateEntityVis(this.model.attributes.entities[i]);
            for (var i in this.model.attributes.acts)
                this.addOrUpdateActVis(this.model.attributes.acts[i]);

            this._network.stabilize();
        },
        prepareModel: function() {
            var m = this.model.attributes;

            m.globalSrc = m.globalSrc || "";
            m.entities = m.entities || [];
            m.acts = m.acts || [];
            m.mappings = m.mappings || [];
        },
        globalSrcChange: function() {
            this.model.set({ globalSrc: this._globalSrcEditor.getValue() });
        },
        validate: function(local) {
            this.model.isValid = true;

            if (!local && this._editor)
                this.model.isValid = this._editor.validate() && this.model.isValid;

            return this.model.isValid;
        },
        triggerModelChanged: function() {
            if(this.validate(true)) {
                this.model.trigger('change', this.model);
            }
        },
        networkSelected: function(e) {
            $(":focus").blur();
            if (e.nodes.length > 0) {
                var n = this._graphNodes.get(e.nodes[0]);

                if (n.dataType == "flow.alien.nls.ad.cl.EntityDescription")
                    this.entitySelected(n.id);
                else if (n.dataType == "flow.alien.nls.ad.cl.XxActDescription" || n.dataType == "flow.alien.nls.ad.cl.XyActDescription")
                    this.actSelected(n.id);
                else if (n.dataType == "flow.alien.nls.ad.cl.XxMappingDescription" || n.dataType == "flow.alien.nls.ad.cl.XyMappingDescription")
                    this.mappingSelected(n.id);
            } else {
                if (this._editor)
                    this._network.selectNodes([this._editor.model.id]);
                else
                    this._network.unselectAll();
            }
        },
        destroyEditor: function() {
            if (this._editor) {
                this._editor.model.unbind("change", this._boundEditorModelChanged);
                this._editor.destroy();
                delete this._editor;
                this.container.empty();
            }
        },
        createEditor: function(e, et) {
            if (!this._editor || this._editor.model.id != e.id) {
                this.destroyEditor();

                var m = new Bb.Model(e);
                m.parent = this.model.attributes;
                this._editor = new et({ model: m, parent: this });
                this._boundEditorModelChanged = _.bind(this.triggerModelChanged, this);
                this._editor.model.bind("change", this._boundEditorModelChanged);
                this.container.append(this._editor.$el);
            }
        },
        entitySelected: function(id) {
            var e = null;

            for (var i in this.model.attributes.entities)
                if (this.model.attributes.entities[i].id == id) {
                    e = this.model.attributes.entities[i];
                    break;
                }

            if (e)
                this.createEditor(e, Flow.Alien.Nls.Ed.Cl.EntityDescriptionEditView)
        },
        actSelected: function(id) {
            var e = null;

            for (var i in this.model.attributes.acts)
                if (this.model.attributes.acts[i].id == id) {
                    e = this.model.attributes.acts[i];
                    break;
                }

            if (e) {
                if (e.dataType == "flow.alien.nls.ad.cl.XxActDescription")
                    this.createEditor(e, Flow.Alien.Nls.Ed.Cl.XxActDescriptionEditView);
                else if (e.dataType == "flow.alien.nls.ad.cl.XyActDescription")
                    this.createEditor(e, Flow.Alien.Nls.Ed.Cl.XyActDescriptionEditView);
            }
        },
        mappingSelected: function(id) {
            var e = null;

            for (var i in this.model.attributes.mappings)
                if (this.model.attributes.mappings[i].id == id) {
                    e = this.model.attributes.mappings[i];
                    break;
                }

            if (e) {
                if (e.dataType == "flow.alien.nls.ad.cl.XxMappingDescription")
                    this.createEditor(e, Flow.Alien.Nls.Ed.Cl.XxMappingDescriptionEditView);
                else if (e.dataType == "flow.alien.nls.ad.cl.XyMappingDescription")
                    this.createEditor(e, Flow.Alien.Nls.Ed.Cl.XyMappingDescriptionEditView);
            }
        },
        addEntity: function() {
            var m = this.model.attributes;
            var e = {
                dataType: "flow.alien.nls.ad.cl.EntityDescription",
                id: Flow.randomId(),
                name: "Unnamed Entity"
            };
            m.entities.push(e);
            this.addOrUpdateEntityVis(e);
            this.entitySelected(e.id);
        },
        addXxAct: function() {
            var m = this.model.attributes;
            var e = {
                dataType: "flow.alien.nls.ad.cl.XxActDescription",
                id: Flow.randomId(),
                name: "Unnamed Act"
            };
            m.acts.push(e);
            this.addOrUpdateActVis(e);
            this.actSelected(e.id);
        },
        addXyAct: function() {
            var m = this.model.attributes;
            var e = {
                dataType: "flow.alien.nls.ad.cl.XyActDescription",
                id: Flow.randomId(),
                name: "Unnamed Act"
            };
            m.acts.push(e);
            this.addOrUpdateActVis(e);
            this.actSelected(e.id);
        },
        addXxMapping: function() {
            var m = this.model.attributes;
            var e = {
                dataType: "flow.alien.nls.ad.cl.XxMappingDescription",
                id: Flow.randomId()
            };
            m.mappings.push(e);
            this.addOrUpdateMappingVis(e);
            this.mappingSelected(e.id);
        },
        addXyMapping: function() {
            var m = this.model.attributes;
            var e = {
                dataType: "flow.alien.nls.ad.cl.XyMappingDescription",
                id: Flow.randomId()
            };
            m.mappings.push(e);
            this.addOrUpdateMappingVis(e);
            this.mappingSelected(e.id);
        },
        deleteSelected: function() {
            var s = this._network.getSelection();
            var m = this.model.attributes;

            if (s.nodes && s.nodes.length > 0) {
                for (var i in s.nodes) {
                    var n = this._graphNodes.get(s.nodes[i]);
                    this.delete(n.id, n.dataType);
                }
            }
        },
        delete: function(id, dataType) {
            if (this._editor && this._editor.model.id == id)
                this.destroyEditor();
            if (dataType == "flow.alien.nls.ad.cl.EntityDescription")
                this.deleteEntity(id);
            else if (dataType == "flow.alien.nls.ad.cl.XxActDescription" || dataType == "flow.alien.nls.ad.cl.XyActDescription")
                this.deleteAct(id);
            else if (dataType == "flow.alien.nls.ad.cl.XxMappingDescription" || dataType == "flow.alien.nls.ad.cl.XyMappingDescription")
                this.deleteMapping(id);

            this.triggerModelChanged();
        },
        deleteEntity: function(id) {
            var m = this.model.attributes;
            for (var j in m.entities) {
                if (m.entities[j].id == id) {
                    var mappingsToDelete = [];
                    for (var k in m.mappings)
                        if (m.mappings[k].xEntity == id || (m.mappings[k].yEntity && m.mappings[k].yEntity == id))
                            mappingsToDelete.push(m.mappings[k].id);
                    for (var k in mappingsToDelete)
                        this.deleteMapping(mappingsToDelete[k]);

                    delete m.entities[j];
                    m.entities.splice(j, 1);
                    this.removeEntityVis(id);
                    break;
                }
            }
        },
        deleteAct: function(id) {
            var m = this.model.attributes;
            for (var j in m.acts) {
                if (m.acts[j].id == id) {
                    var mappingsToDelete = [];
                    for (var k in m.mappings)
                        if (m.mappings[k].act == id)
                            mappingsToDelete.push(m.mappings[k].id);
                    for (var k in mappingsToDelete)
                        this.deleteMapping(mappingsToDelete[k]);

                    delete m.acts[j];
                    m.acts.splice(j, 1);
                    this.removeActVis(id);
                    break;
                }
            }
        },
        deleteMapping: function(id) {
            var m = this.model.attributes;
            for (var j in m.mappings) {
                if (m.mappings[j].id == id) {
                    delete m.mappings[j];
                    m.mappings.splice(j, 1);
                    this.removeMappingVis(id);
                    break;
                }
            }
        },
        addOrUpdateEntityVis: function(e) {
            if (!this._graphNodes.get(e.id))
                this._graphNodes.add({ id: e.id, group: "entity", dataType: e.dataType, label: e.name, mass: 3, shape: "box" });
            else
                this._graphNodes.update({ id: e.id, dataType: e.dataType, label: e.name });

            this._network.selectNodes([e.id]);
        },
        addOrUpdateActVis: function(e) {
            if (!this._graphNodes.get(e.id))
                this._graphNodes.add({ id: e.id, group: "act", dataType: e.dataType, label: e.name, shape: "ellipse", mass: e.measurement ? 1 : 2, shadow: { enabled: e.measurement ? true : false } });
            else
                this._graphNodes.update({ id: e.id, dataType: e.dataType, label: e.name, mass: e.measurement ? 1 : 2, shadow: { enabled: e.measurement ? true : false } });

            for (var i in this.model.attributes.mappings)
                if (this.model.attributes.mappings[i].act == e.id)
                    this.addOrUpdateMappingVis(this.model.attributes.mappings[i]);

            this._network.selectNodes([e.id]);
        },
        addOrUpdateMappingVis: function(e) {
            var m = this.model.attributes;

            var act = null;
            for (var i in this.model.attributes.acts)
                if (this.model.attributes.acts[i].id == e.act) {
                    act = this.model.attributes.acts[i];
                    break;
                }
            act = act || { measurement: true };

            if (!this._graphNodes.get(e.id))
                this._graphNodes.add({ id: e.id, group: "mapping", dataType: e.dataType, shape: "dot", size: 5, mass: act.measurement ? 0.25 : 0.5, shadow: { enabled: act.measurement ? true : false } });
            else {
                this._graphNodes.update({ id: e.id, dataType: e.dataType, mass: act.measurement ? 0.25 : 0.5, shadow: { enabled: act.measurement ? true : false } });
                this._graphEdges.remove(e.id + "ef");
                this._graphEdges.remove(e.id + "x");
                this._graphEdges.remove(e.id + "y");
            }

            if (e.act)
                this._graphEdges.add({ id: e.id + "ef", from: e.act, to: e.id });
            if (e.xEntity)
                this._graphEdges.add({ id: e.id + "x", from: e.xEntity, to: e.id });
            if (e.yEntity)
                this._graphEdges.add({ id: e.id + "y", from: e.id, to: e.yEntity });

            this._network.selectNodes([e.id]);
        },
        removeEntityVis: function(id) {
            this._graphNodes.remove(id);
        },
        removeActVis: function(id) {
            this._graphNodes.remove(id);
        },
        removeMappingVis: function(id) {
            this._graphEdges.remove(id + "ef");
            this._graphEdges.remove(id + "in");
            this._graphEdges.remove(id + "out");
            this._graphNodes.remove(id);
        },
        selectAct: function(e) {
            console.log(e);
        }
    });

    Flow.Alien.Nls.Ed.Cl.EntityDescriptionEditView = Ep.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Alien-Nls-Ed-Cl-EntityDescriptionEditView").html())),
        events: {
            "click #txtName": "enqueueUpdateVis",
        },
        bindings: {
            "#txtName": "value:name",
            "#txtAmount": "value:amountString"
        },
        initialize: function(o) {
            this.parent = o.parent;
            this.model.owner = this;
            this._boundModelChanged = _.bind(this.modelChanged, this);
            this.model.bind("change", this._boundModelChanged);
            this.render();
        },
        modelChanged: function(m) {
            if(this.validate(true)) {
                var amount = parseInt(m.attributes.amountString);
                if(amount > 0)
                    m.attributes.amount = amount;
                
                m.owner.parent.updateEntity(m.attributes);
                if(m.owner._updateVis)
                    m.owner.parent.addOrUpdateEntityVis(m.attributes);
            }
        },
        enqueueUpdateVis: function() {
            this._updateVis = true;
        },
        destroy: function() {
            this.model.unbind("change", _.bind(this.modelChanged, this));
            this.remove();
            this.unbind();
        },
        createSrcEditor: function(e, p, c) {
            var editor = Ace.edit(e);
            editor.owner = this;
            editor.property = p;
            editor.setOptions({ maxLines: 29 });
            editor.setTheme("ace/theme/iplastic");
            editor.setHighlightActiveLine(false);
            editor.getSession().setMode("ace/mode/c_cpp");
            editor.setValue(this.model.get(p));
            editor.getSession().on('change', c);

            return editor;
        },
        render: function() {
            this.prepareModel();
            this.$el.html(this.template(this.model));
            this.applyBindings();
            
            this._paramSrcEditor = this.createSrcEditor(
                this.$("#paramSrcEditor")[0], "paramSrc", _.bind(this.paramSrcChange, this)
            );

            this.validate(true);

            return this;
        },
        prepareModel: function() {
            var m = this.model.attributes;
            m.name = m.name || "";
            m.amount = m.amount || 1;
            m.paramSrc = m.paramSrc || "";

            m.amountString = m.amount.toString();
        },
        paramSrcChange: function() {
            this.model.set({ paramSrc: this._paramSrcEditor.getValue() });
        },
        validate: function(local) {
            var d = this.model.attributes;
            this.model.isValid = true;
            
            try {
                this.model.isValid = Flow.Validations.stringNull(
                    d.name, this.$("#groupName"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}

            return this.model.isValid;
        }
    });

    Flow.Alien.Nls.Ed.Cl.InformationDescriptionView = Ep.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Alien-Nls-Ed-Cl-InformationDescriptionView").html())),
        events: {
            "click #btnDelete": "del",
        },
        bindings: {
            "#txtInfoName": "value:name",
            "#selType": "value:typeString",
            "#txtDimensions": "value:dimensionsString",
            "#chkAbsolute": "checked:isAbsolute"
        },
        initialize: function(o) {
            this.parent = o.parent;
            this.model.owner = this;
            this._boundModelChanged = _.bind(this.modelChanged, this);
            this.model.bind("change", this._boundModelChanged);
            this.render();
        },
        modelChanged: function(m) {
            if(this.validate(true)) {
                m.attributes.type = parseInt(m.attributes.typeString);

                var dims = m.attributes.dimensionsString.split("*");
                m.attributes.dimensions = [];
                for(var i in dims)
                    m.attributes.dimensions.push(parseInt(dims[i]));

                m.owner.parent.update(m.attributes);
            }
        },
        destroy: function() {
            this.model.unbind("change", _.bind(this.modelChanged, this));
            this.remove();
            this.unbind();
        },
        render: function() {
            this.prepareModel();
            this.$el.html(this.template(this.model));
            this.applyBindings();

            this.validate(true);

            return this;
        },
        prepareModel: function() {
            var m = this.model.attributes;
            m.typeString = m.type.toString();
            m.dimensionsString = "";
            for (var i in m.dimensions) {
                if (m.dimensionsString.length !== 0)
                    m.dimensionsString = m.dimensionsString + "*";
                m.dimensionsString = m.dimensionsString + m.dimensions[i];
            }
        },
        del: function() {
            this.parent.remove(this.model.attributes.id);
        },
        validate: function(local) {
            var d = this.model.attributes;
            this.model.isValid = true;
            
            try {
                this.model.isValid = Flow.Validations.stringNull(
                    d.name, this.$("#groupName"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}
            
            try {
                this.model.isValid = Flow.Validations.stringNull(
                    d.dimensionsString, this.$("#groupDimensions"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}

            return this.model.isValid;
        }
    });

    Flow.Alien.Nls.Ed.Cl.InformationDescriptionListView = Bb.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Alien-Nls-Ed-Cl-InformationDescriptionListView").html())),
        events: {
            "click #btnAdd": "add",
        },
        initialize: function(o) {
            this.infoEditors = [];
            this._boundModelChanged = _.bind(this.modelChanged, this);
            this.model.bind("change", this._boundModelChanged);
            this.render();
        },
        modelChanged: function(m) {
            this.validate(true);
        },
        destroy: function() {
            this.model.unbind("change", _.bind(this.modelChanged, this));
            this.remove();
            this.unbind();
        },
        render: function() {
            this.$el.html(this.template(this.model));
            this.container = this.$("#body");
            this._boundInfoModelChanged = _.bind(this.triggerModelChanged, this);

            for (var i in this.model.attributes.list) {
                this.add(this.model.attributes.list[i]);
            }

            return this;
        },
        add: function(info) {
            if (!info.id) {
                info = {
                    dataType: "flow.alien.nls.ad.cl.InformationDescription",
                    id: Flow.randomId(),
                    name: "",
                    type: 0,
                    dimensions: [1],
                    isAbsolute: false
                };
                this.model.attributes.list.push(info);
                this.triggerModelChanged();
            }

            this.infoEditors[info.id] = new Flow.Alien.Nls.Ed.Cl.InformationDescriptionView({ parent: this, model: new Bb.Model(info) });
            this.infoEditors[info.id].model.bind("change", this._boundInfoModelChanged);
            this.container.append(this.infoEditors[info.id].$el);
        },
        update: function(info) {
            for (var i in this.model.attributes.list)
                    if (this.model.attributes.list[i].id == info.id) {
                        this.model.attributes.list[i] = info;
                        this.triggerModelChanged();
                        break;
                    }
        },
        remove: function(id) {
            if (id in this.infoEditors) {
                for (var i in this.model.attributes.list)
                    if (this.model.attributes.list[i].id == id) {
                        this.model.attributes.list.splice(i, 1);
                        this.triggerModelChanged();
                        break;
                    }

                this.infoEditors[id].model.unbind("change", this._boundInfoModelChanged);
                this.infoEditors[id].destroy();
                delete this.infoEditors[id];
            }
        },
        triggerModelChanged: function() {
            if(this.validate(true)) {
                this.model.trigger('change', this.model);
            }
        },
        validate: function(local) {
            this.model.isValid = true;

            if(!local)
                for(var i in this.infoEditors)
                    this.model.isValid = this.infoEditors[i].validate() && this.model.isValid;

            return this.model.isValid;
        }
    });

    Flow.Alien.Nls.Ed.Cl.XxActDescriptionEditView = Ep.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Alien-Nls-Ed-Cl-XxActDescriptionEditView").html())),
        events: {
            "click #btnxInformation": "showxInformation",
            "click #btnActSrc": "showActSrc",
            "click #txtName": "enqueueUpdateVis",
            "click #chkMeasurement": "enqueueUpdateVis"
        },
        bindings: {
            "#txtName": "value:name",
            "#chkMeasurement": "checked:measurement"
        },
        initialize: function(o) {
            this.parent = o.parent;
            this.model.owner = this;
            this._boundModelChanged = _.bind(this.modelChanged, this);
            this.model.bind("change", this._boundModelChanged);
            this.render();
        },
        modelChanged: function(m) {
            if(this.validate(true)) {
                m.owner.parent.updateAct(m.attributes);
                if (m.owner._updateVis) {
                    m.owner.parent.addOrUpdateActVis(m.attributes);
                    m.owner._updateVis = false;
                }
            }
        },
        enqueueUpdateVis: function() {
            this._updateVis = true;
        },
        destroy: function() {
            this.xInfosList.model.unbind("change", this._boundInfosListModelChanged);
            this.xInfosList.destroy();

            this.model.unbind("change", this._boundModelChanged);
            this.remove();
            this.unbind();
        },
        render: function() {
            this.prepareModel();
            this.$el.html(this.template(this.model));
            this.applyBindings();

            this._boundInfosListModelChanged = _.bind(this.triggerModelChanged, this);
            this.xInfosList = new Flow.Alien.Nls.Ed.Cl.InformationDescriptionListView({ el: this.$("#pnlxInformation"), model: new Bb.Model({ list: this.model.attributes.xInfos }) });
            this.xInfosList.model.bind("change", this._boundInfosListModelChanged);


            this._actSrcEditor = this.createSrcEditor(
                this.$("#actSrcEditor")[0], "actSrc", _.bind(this.actSrcChange, this)
            );

            this.validate(true);

            return this;
        },
        triggerModelChanged: function() {
            if(this.validate(true)) {
                this.model.trigger('change', this.model);
            }
        },
        createSrcEditor: function(e, p, c) {
            var editor = Ace.edit(e);
            editor.owner = this;
            editor.property = p;
            editor.setOptions({ maxLines: 25 });
            editor.setTheme("ace/theme/iplastic");
            editor.setHighlightActiveLine(false);
            editor.getSession().setMode("ace/mode/c_cpp");
            editor.setValue(this.model.get(p));
            editor.getSession().on('change', c);

            return editor;
        },
        triggerModelChanged: function() {
            if(this.validate(true)) {
                this.model.trigger('change', this.model);
            }
        },
        prepareModel: function() {
            var m = this.model.attributes;
            m.name = m.name || "";
            m.measurement = m.measurement || false;
            m.xInfos = m.xInfos || [];
            m.actSrc = m.actSrc || "";
        },
        actSrcChange: function() {
            this.model.set({ actSrc: this._actSrcEditor.getValue() });
        },
        showPanel: function(e) {
            this._active = e;
            this.$("#btn" + e).addClass("active");
            this.$("#pnl" + e).show();
        },
        hidePanel: function(e) {
            this.$("#btn" + e).removeClass("active");
            this.$("#pnl" + e).hide();
        },
        hideAllPanels: function() {
            this.hidePanel("xInformation");
            this.hidePanel("ActSrc");
        },
        showxInformation: function() {
            this.hideAllPanels();
            this.showPanel("xInformation");
        },
        showActSrc: function() {
            this.hideAllPanels();
            this.showPanel("ActSrc");
        },
        validate: function(local) {
            var d = this.model.attributes;
            this.model.isValid = true;
            
            try {
                this.model.isValid = Flow.Validations.stringNull(
                    d.name, this.$("#groupName"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}

            if(!local)
                this.model.isValid = this.xInfosList.validate() && this.model.isValid;

            return this.model.isValid;
        }
    });

    Flow.Alien.Nls.Ed.Cl.XyActDescriptionEditView = Ep.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Alien-Nls-Ed-Cl-XyActDescriptionEditView").html())),
        events: {
            "click #btnxInformation": "showxInformation",
            "click #btnyInformation": "showyInformation",
            "click #btnActSrc": "showActSrc",
            "click #btnJoinSrc": "showJoinSrc",
            "click #btnSaveActSrc": "saveActSrc",
            "click #btnSaveJoinSrc": "saveJoinSrc",
            "click #txtName": "enqueueUpdateVis",
            "click #chkMeasurement": "enqueueUpdateVis"
        },
        bindings: {
            "#txtName": "value:name",
            "#chkMeasurement": "checked:measurement"
        },
        initialize: function(o) {
            this.parent = o.parent;
            this.model.owner = this;
            this._boundModelChanged = _.bind(this.modelChanged, this);
            this.model.bind("change", this._boundModelChanged);
            this.render();
        },
        modelChanged: function(m) {
            if(this.validate(true)) {
                m.owner.parent.updateAct(m.attributes);
                if (m.owner._updateVis) {
                    m.owner.parent.addOrUpdateActVis(m.attributes);
                    m.owner._updateVis = false;
                }
            }
        },
        enqueueUpdateVis: function() {
            this._updateVis = true;
        },
        destroy: function() {
            this.xInfosList.model.unbind("change", this._boundInfosListModelChanged);
            this.yInfosList.model.unbind("change", this._boundInfosListModelChanged);
            this.xInfosList.destroy();
            this.yInfosList.destroy();
            this.model.unbind("change", this._boundModelChanged);
            this.remove();
            this.unbind();
        },
        render: function() {
            this.prepareModel();
            this.$el.html(this.template(this.model));
            this.applyBindings();

            this._boundInfosListModelChanged = _.bind(this.triggerModelChanged, this);
            this.xInfosList = new Flow.Alien.Nls.Ed.Cl.InformationDescriptionListView({ el: this.$("#pnlxInformation"), model: new Bb.Model({ list: this.model.attributes.xInfos }) });
            this.xInfosList.model.bind("change", this._boundInfosListModelChanged);
            this.yInfosList = new Flow.Alien.Nls.Ed.Cl.InformationDescriptionListView({ el: this.$("#pnlyInformation"), model: new Bb.Model({ list: this.model.attributes.yInfos }) });
            this.yInfosList.model.bind("change", this._boundInfosListModelChanged);

            this._actSrcEditor = this.createSrcEditor(
                this.$("#actSrcEditor")[0], "actSrc", _.bind(this.actSrcChange, this)
            );
            this._joinSrcEditor = this.createSrcEditor(
                this.$("#joinSrcEditor")[0], "joinSrc", _.bind(this.joinSrcChange, this)
            );

            this.validate(true);

            return this;
        },
        triggerModelChanged: function() {
            if(this.validate(true)) {
                this.model.trigger('change', this.model);
            }
        },
        createSrcEditor: function(e, p, c) {
            var editor = Ace.edit(e);
            editor.owner = this;
            editor.property = p;
            editor.setOptions({ maxLines: 25 });
            editor.setTheme("ace/theme/iplastic");
            editor.setHighlightActiveLine(false);
            editor.getSession().setMode("ace/mode/c_cpp");
            editor.setValue(this.model.get(p));
            editor.getSession().on('change', c);

            return editor;
        },
        triggerModelChanged: function() {
            if(this.validate(true)) {
                this.model.trigger('change', this.model);
            }
        },
        prepareModel: function() {
            var m = this.model.attributes;
            m.name = m.name || "";
            m.measurement = m.measurement || false;
            m.xInfos = m.xInfos || [];
            m.yInfos = m.yInfos || [];
            m.actSrc = m.actSrc || "";
            m.joinSrc = m.joinSrc || "";
        },
        actSrcChange: function() {
            this.model.set({ actSrc: this._actSrcEditor.getValue() });
        },
        joinSrcChange: function() {
            this.model.set({ joinSrc: this._joinSrcEditor.getValue() });
        },
        showPanel: function(e) {
            this._active = e;
            this.$("#btn" + e).addClass("active");
            this.$("#pnl" + e).show();
        },
        hidePanel: function(e) {
            this.$("#btn" + e).removeClass("active");
            this.$("#pnl" + e).hide();
        },
        hideAllPanels: function() {
            this.hidePanel("xInformation");
            this.hidePanel("yInformation");
            this.hidePanel("ActSrc");
            this.hidePanel("JoinSrc");
        },
        showxInformation: function() {
            this.hideAllPanels();
            this.showPanel("xInformation");
        },
        showyInformation: function() {
            this.hideAllPanels();
            this.showPanel("yInformation");
        },
        showActSrc: function() {
            this.hideAllPanels();
            this.showPanel("ActSrc");
        },
        showJoinSrc: function() {
            this.hideAllPanels();
            this.showPanel("JoinSrc");
        },
        validate: function(local) {
            var d = this.model.attributes;
            this.model.isValid = true;
            
            try {
                this.model.isValid = Flow.Validations.stringNull(
                    d.name, this.$("#groupName"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}

            if(!local) {
                this.model.isValid = this.xInfosList.validate() && this.model.isValid;
                this.model.isValid = this.xInfosList.validate() && this.model.isValid;
            }

            return this.model.isValid;
        }
    });

    Flow.Alien.Nls.Ed.Cl.XxMappingDescriptionEditView = Ep.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Alien-Nls-Ed-Cl-XxMappingDescriptionEditView").html())),
        bindings: {
            "#selAct": "value:act",
            "#selxEntity": "value:xEntity"
        },
        initialize: function(o) {
            this.parent = o.parent;
            this.model.owner = this;
            this._boundModelChanged = _.bind(this.modelChanged, this);
            this.model.bind("change", this._boundModelChanged);
            this.render();
        },
        modelChanged: function(m) {
            if(this.validate(true)) {
                m.owner.parent.updateMapping(m.attributes);
                m.owner.parent.addOrUpdateMappingVis(m.attributes);
            }
        },
        destroy: function() {
            this.model.unbind("change", this._boundModelChanged);
            this.remove();
            this.unbind();
        },
        render: function() {
            this.prepareModel();
            this.$el.html(this.template(this.model));
            this.applyBindings();

            this.validate(true);

            return this;
        },
        prepareModel: function() {
            var m = this.model.attributes;
            m.act = m.act || Flow.emptyId();
            m.xEntity = m.xEntity || Flow.emptyId();
        },
        validate: function(local) {
            var d = this.model.attributes;
            this.model.isValid = true;
            
            try {
                this.model.isValid = Flow.Validations.idNull(
                    d.act, this.$("#groupAct"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}
            
            try {
                this.model.isValid = Flow.Validations.idNull(
                    d.xEntity, this.$("#groupxEntity"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}

            return this.model.isValid;
        }
    });

    Flow.Alien.Nls.Ed.Cl.XyMappingDescriptionEditView = Ep.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Alien-Nls-Ed-Cl-XyMappingDescriptionEditView").html())),
        bindings: {
            "#selAct": "value:act",
            "#selxEntity": "value:xEntity",
            "#selyEntity": "value:yEntity"
        },
        initialize: function(o) {
            this.parent = o.parent;
            this.model.owner = this;
            this._boundModelChanged = _.bind(this.modelChanged, this);
            this.model.bind("change", this._boundModelChanged);
            this.render();
        },
        modelChanged: function(m) {
            if(this.validate(true)) {
                m.owner.parent.updateMapping(m.attributes);
                m.owner.parent.addOrUpdateMappingVis(m.attributes);
            }
        },
        destroy: function() {
            this.model.unbind("change", this._boundModelChanged);
            this.remove();
            this.unbind();
        },
        render: function() {
            this.prepareModel();
            this.$el.html(this.template(this.model));
            this.applyBindings();

            this.validate(true);

            return this;
        },
        prepareModel: function() {
            var m = this.model.attributes;
            m.act = m.act || Flow.emptyId();
            m.xEntity = m.xEntity || Flow.emptyId();
            m.yEntity = m.yEntity || Flow.emptyId();
        },
        validate: function(local) {
            var d = this.model.attributes;
            this.model.isValid = true;
            
            try {
                this.model.isValid = Flow.Validations.idNull(
                    d.act, this.$("#groupAct"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}
            
            try {
                this.model.isValid = Flow.Validations.idNull(
                    d.xEntity, this.$("#groupxEntity"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}
            
            try {
                this.model.isValid = Flow.Validations.idNull(
                    d.yEntity, this.$("#groupyEntity"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}

            return this.model.isValid;
        }
    });

    Flow.service.registerInit(function() {
        // registering views for editing data
        Flow.host.registerDataEditor("flow.alien.nls.ad.cl.Description", Flow.Alien.Nls.Ed.Cl.DescriptionEditView);
    });
});