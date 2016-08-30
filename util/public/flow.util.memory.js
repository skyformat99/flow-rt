define(["flow", "jquery", "backbone", "backbone.epoxy", "underscore", "text!flow.util.memory.html"], function(Flow, $, Bb, Ep, _, tpl){
    var Flow = Flow || {};
    Flow.Util = Flow.Util || {};
    Flow.Util.Memory = Flow.Util.Memory || {};
    Flow.Util.Memory.memoryEditStoreWaiters = [];
    Flow.Util.Memory.memoryExports = [];
    
    Flow.service.registerInit(function() {
        // registering views for entities
        Flow.tick.overview.register("flow.util.memory.Memory", Flow.Util.Memory.MemoryEntityView);

        Flow.service.beginListen("flow.util.memory.OverviewResponse", function(s) {
            for(i in s.data.data) {
                Flow.service.send({
                    dataType: "flow.util.memory.InfoRequest",
                    data: s.data.data[i]
                }, s.source);
            }
        });
        
        Flow.service.beginListen("flow.util.memory.AddedMsg", function(s) {
            Flow.service.send({
                dataType: "flow.util.memory.InfoRequest",
                data: s.data
            }, s.source);
        });
        
        Flow.service.beginListen("flow.util.memory.UpdateMsg", function(s) {
            Flow.service.send({
                dataType: "flow.util.memory.InfoRequest",
                data: s.data
            }, s.source);
        });
        
        Flow.service.beginListen("flow.util.memory.RemoveMsg", function(s) {
            if(s.source.id in Flow.tick.overview.entityViews) {
                var view = Flow.tick.overview.entityViews[s.source.id];

                if(s.data in view.infos)
                    view.removeItem(s.data);
            }
        });
        
        Flow.service.beginListen("flow.util.memory.StoreSuccessMsg", function(s) {
            if(s.source.id in Flow.tick.overview.entityViews) {
                if(s.group in Flow.Util.Memory.memoryEditStoreWaiters) {
                    var v = Flow.Util.Memory.memoryEditStoreWaiters[s.group];
                    if(v.dirty) { v.dirty = false;
                        v.$("#btnSave").removeClass("btn-primary");
                        v.$("#btnSave").addClass("btn-default");
                    }

                    delete Flow.Util.Memory.memoryEditStoreWaiters[s.group];
                }
            }
        });
        
        Flow.service.beginListen("flow.util.memory.StoreFailedMsg", function(s) {
            alert("add/update of memory failed");
        });
        
        Flow.service.beginListen("flow.util.memory.IncompatibleMemory", function(s) {
            alert("add/update of memory failed");
        });
        
        Flow.service.beginListen("flow.util.memory.RemoveFailedMsg", function(s) {
            alert("remove of memory failed");
        });
        
        Flow.service.beginListen("flow.util.memory.NotFoundMsg", function(s) {
            alert("memory with id " + s.data + " was not found");
        });

        Flow.service.beginListen("flow.util.memory.InfoResponse", function(s) {
            if(s.source.id in Flow.tick.overview.entityViews) {
                var view = Flow.tick.overview.entityViews[s.source.id];
                view.addOrUpdateItem(s.data);
            }
        });

        Flow.service.beginListen("flow.util.memory.Response", function(s) {
            if(s.group in Flow.Util.Memory.memoryExports) {
                var view = Flow.Util.Memory.memoryExports[s.group];
                delete Flow.Util.Memory.memoryExports[s.group];
                view.downloadItem(s.data);
            } else if(s.data.data.dataType in Flow.host.dataEditorTypes) {
                var editor = new Flow.Util.Memory.MemoryEditView({model: new Bb.Model(s.data), memory: s.source});
                Flow.tickManager.run(editor);
            }
            else
            {
                alert("got data of type \""+s.data.data.dataType+"\" but there is no editor for it registered!");
            }
        });
    });

    Flow.Util.Memory.MemoryEntityView = Bb.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Util-Memory-MemoryEntityView").html())),
        events: {
            "click #btnCreate": "createItem",
            "click #btnImport": "importItem",
        },
        initialize: function(entity) {
            this.infos = [];

            this.refresh(entity);
            this.render();
            Flow.service.addListenSource("flow.util.memory.OverviewResponse", entity.id);
            Flow.service.addListenSource("flow.util.memory.AddedMsg", entity.id);
            Flow.service.addListenSource("flow.util.memory.UpdateMsg", entity.id);
            Flow.service.addListenSource("flow.util.memory.RemoveMsg", entity.id);
            Flow.service.addListenSource("flow.util.memory.StoreSuccessMsg", entity.id);
            Flow.service.addListenSource("flow.util.memory.StoreFailedMsg", entity.id);
            Flow.service.addListenSource("flow.util.memory.IncompatibleMemory", entity.id);
            Flow.service.addListenSource("flow.util.memory.RemoveFailedMsg", entity.id);
            Flow.service.addListenSource("flow.util.memory.InfoResponse", entity.id);
            Flow.service.addListenSource("flow.util.memory.Response", entity.id);

            Flow.service.send({
                dataType: "flow.util.memory.OverviewRequest"
            }, this.entity);
        },
        destroy: function() {
            this.remove();
            this.unbind();
        },
        render: function() {
            this.$el.html(this.template(this.entity.attributes));
            this.container = this.$("#body");
            return this;
        },
        refresh: function(entity) {
            this.entity = entity;
        },
        addOrUpdateItem: function(info) {
            if(info.id in this.infos) {
                this.infos[info.id].refresh(info);
            } else {
                this.infos[info.id] = new Flow.Util.Memory.MemoryItemView({entity: this.entity, model: info});
                this.infos[info.id].$el.addClass("memory");
                this.container.append(this.infos[info.id].$el);
            }
        },
        removeItem: function(id) {
            if(id in this.infos) {
                this.infos[id].destroy();
                delete this.infos[id];
            }
        },
        createItem: function(e) {
            Flow.service.send({
                dataType: "flow.util.memory.RequestNew",
                data: e.currentTarget.innerText
            }, this.entity);
        },
        importItem: function() {
            var element = document.createElement('div');
            element.innerHTML = '<input type="file">';
            var fileInput = element.firstChild;
            var memory = this.entity;
            fileInput.addEventListener('change', function() {
                var file = fileInput.files[0];

                if (file.name.match(/\.memory$/)) {
                    var reader = new FileReader();

                    reader.onload = function() {
                        var data = JSON.parse(reader.result);
                        var canHandle = false;
                        for(i in memory.attributes.settings.types)
                            if(data.data.dataType == memory.attributes.settings.types[i])
                                canHandle = true;
                        
                        if(canHandle)
                            Flow.service.send({
                                dataType: "flow.util.memory.StoreRequest",
                                data: data
                            }, memory);
                        else alert("memory does not support memory of type \""+data.data.dataType+"\"");
                    };

                    reader.readAsText(file);    
                } else {
                    alert("File not supported, .memory files only");
                }
            });

            fileInput.click();
        }
    });

    Flow.Util.Memory.MemoryItemView = Bb.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Util-Memory-MemoryItemView").html())),
        events: {
            "click #btnEdit": "editItem",
            "click #btnRemove": "removeItem",
            "click #btnExport": "exportItem",
        },
        initialize: function(o) {
            this.entity = o.entity;
            this.render();
        },
        destroy: function() {
            this.remove();
            this.unbind();
        },
        render: function() {
            this.prepareModel();
            this.$el.html(this.template(this.model));
            return this;
        },
        refresh: function(info) {
            this.model = info;
            this.render();
        },
        prepareModel: function() {
            var a = this.model;
            a.name = a.name || "";
            a.description = a.description || "";
        },
        editItem: function(e) {
            Flow.service.send({
                dataType: "flow.util.memory.Request",
                data: {
                    dataType: "flow.util.memory.RequestInfo", 
                    id: this.model.id,
                    revision: parseInt(e.currentTarget.getAttribute("revision"))
                }
            }, this.entity);
        },
        exportItem: function(e) {
            var group = Flow.randomId();
            Flow.Util.Memory.memoryExports[group] = this;

            Flow.service.send({
                dataType: "flow.util.memory.Request",
                group: group,
                data: {
                    dataType: "flow.util.memory.RequestInfo",
                    id: this.model.id,
                    revision: parseInt(e.currentTarget.getAttribute("revision"))
                }
            }, this.entity);
        },
        downloadItem: function(data) {
            if(!data) {
                console.error('No data');
                return;
            }

            var filename = data.name+".memory";

            if(typeof data === "object"){
                data = JSON.stringify(data, undefined, 4);
            }

            var blob = new Blob([data], {type: 'text/json'}),
                e    = document.createEvent('MouseEvents'),
                a    = document.createElement('a');

            a.download = filename;
            a.href = window.URL.createObjectURL(blob);
            a.dataset.downloadurl =  ['text/json', a.download, a.href].join(':');
            e.initMouseEvent('click', true, false, window, 0, 0, 0, 0, 0, false, false, false, false, 0, null);
            a.dispatchEvent(e);
        },
        removeItem: function() {
            Flow.service.send({
                dataType: "flow.util.memory.RemoveRequest",
                data: this.model.id
            }, this.entity);
        },
    });

    Flow.Util.Memory.MemoryEditView = Ep.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Util-Memory-MemoryEditView").html())),
        events: {
            "click #btnSave": "save",
        },
        bindings: {
            "#txtName": "value:name",
            "#txtDescription": "value:description"
        },
        initialize: function(o) {
            this.memory = o.memory;
            this._boundModelChanged = _.bind(this.modelChanged, this);
            this.model.bind("change", this._boundModelChanged);
            this.type = this.model.attributes.data.dataType;
            if(this.type in Flow.host.dataEditorTypes)
                this.render();
        },
        modelChanged: function(m) {
            if(!this.dirty) {
                this.dirty = true;
                this.$("#btnSave").removeClass("btn-default");
                this.$("#btnSave").addClass("btn-primary");
            }
        },
        destroy: function() {
            $(window).unbind("keydown", this._boundHandleKeydown);
            this.remove();
            this.unbind();
            this.editor.model.unbind("change", this._boundEditorModelChanged);
            this.model.unbind("change", this._boundModelChanged);

            if(this.editor.destroy)
            this.editor.destroy();
        },
        render: function() {
            this.prepareModel();
            this.$el.html(this.template(this.model.attributes));
            this.container = this.$("#body");
            var emodel = new Bb.Model(this.model.attributes.data);
            emodel.id = this.model.attributes.id;
            this.editor = new Flow.host.dataEditorTypes[this.type]({el: this.container, model: emodel});
            this._boundEditorModelChanged = _.bind(this.triggerModelChanged, this);
            this.editor.model.bind("change", this._boundEditorModelChanged);
            this.validate();

            this._boundHandleKeydown = _.bind(this.handleKeydown, this);
            $(window).bind("keydown", this._boundHandleKeydown);

            return this;
        },
        handleKeydown: function(e) {
            if (event.ctrlKey || event.metaKey) {
                switch (String.fromCharCode(event.which).toLowerCase()) {
                case 's':
                    event.preventDefault();
                    this.save();
                    break;
                }
            }
        },
        triggerModelChanged: function() {
            this.model.trigger('change', this.model);
        },
        focus: function() {this.$(".focus").focus();},
        getDisplay: function() {
            var display = _.template(_.unescape($(tpl).filter("#Flow-Util-Memory-MemoryEditView-display").html()))(this.model.attributes);
            return display;
        },
        prepareModel: function() {
            var m = this.model.attributes;
            m.name = m.name || "";
            m.description = m.description || "";
        },
        save: function() {
            var group = Flow.randomId();
            Flow.Util.Memory.memoryEditStoreWaiters[group] = this;
            this.validate();
            if(this.model.isValid) {
                this.model.attributes.data = this.editor.model.attributes;
                Flow.service.send({
                    dataType: "flow.util.memory.StoreRequest",
                    group: group,
                    data: this.model
                }, this.memory);
            }
        },
        validate: function() {
            var d = this.model.attributes;
            this.model.isValid = true;
            
            try {
                this.model.isValid = Flow.Validations.stringNull(
                    d.name, this.$("#groupName"), "has-error")
                    && this.model.isValid;
            }
            catch(err) {this.model.isValid = false;}

            if(this.editor.validate)
                this.model.isValid = this.editor.validate() && this.model.isValid;

            return this.model.isValid;
        },
    });
});