define(["flow", "jquery", "backbone", "backbone.epoxy", "underscore", "text!flow.data.memory.html"], function(Flow, $, Bb, Ep, _, tpl){
    var Flow = Flow || {};
    Flow.Data = Flow.Data || {};
    Flow.Data.Memory = Flow.Data.Memory || {};
    Flow.Data.Memory.memoryEditStoreWaiters = [];
    Flow.Data.Memory.memoryExports = [];
    
    Flow.service.registerInit(function() {
        // registering views for entities
        Flow.tick.overview.register("flow.data.memory.Memory", Flow.Data.Memory.MemoryEntityView);

        Flow.service.beginListen("flow.data.memory.OverviewResponse", function(s) {
            for(i in s.data.data) {
                Flow.service.send({
                    dataType: "flow.data.memory.InfoRequest",
                    data: s.data.data[i]
                }, s.source);
            }
        });
        
        Flow.service.beginListen("flow.data.memory.AddedMsg", function(s) {
            Flow.service.send({
                dataType: "flow.data.memory.InfoRequest",
                data: s.data
            }, s.source);
        });
        
        Flow.service.beginListen("flow.data.memory.UpdateMsg", function(s) {
            Flow.service.send({
                dataType: "flow.data.memory.InfoRequest",
                data: s.data
            }, s.source);
        });
        
        Flow.service.beginListen("flow.data.memory.RemoveMsg", function(s) {
            if(s.source.id in Flow.tick.overview.entityViews) {
                var view = Flow.tick.overview.entityViews[s.source.id];

                if(s.data in view.infos)
                    view.removeItem(s.data);
            }
        });
        
        Flow.service.beginListen("flow.data.memory.StoreSuccessMsg", function(s) {
            if(s.source.id in Flow.tick.overview.entityViews) {
                if(s.group in Flow.Data.Memory.memoryEditStoreWaiters) {
                    var v = Flow.Data.Memory.memoryEditStoreWaiters[s.group];
                    if(v.dirty) { v.dirty = false;
                        v.$("#btnSave").removeClass("btn-primary");
                        v.$("#btnSave").addClass("btn-default");
                    }

                    delete Flow.Data.Memory.memoryEditStoreWaiters[s.group];
                }
            }
        });
        
        Flow.service.beginListen("flow.data.memory.StoreFailedMsg", function(s) {
            alert("add/update of memory failed");
        });
        
        Flow.service.beginListen("flow.data.memory.IncompatibleMemory", function(s) {
            alert("add/update of memory failed");
        });
        
        Flow.service.beginListen("flow.data.memory.RemoveFailedMsg", function(s) {
            alert("remove of memory failed");
        });
        
        Flow.service.beginListen("flow.data.memory.NotFoundMsg", function(s) {
            alert("memory with id " + s.data + " was not found");
        });

        Flow.service.beginListen("flow.data.memory.InfoResponse", function(s) {
            if(s.source.id in Flow.tick.overview.entityViews) {
                var view = Flow.tick.overview.entityViews[s.source.id];
                view.addOrUpdateItem(s.data);
            }
        });

        Flow.service.beginListen("flow.data.memory.Response", function(s) {
            if(s.group in Flow.Data.Memory.memoryExports) {
                var view = Flow.Data.Memory.memoryExports[s.group];
                delete Flow.Data.Memory.memoryExports[s.group];
                view.downloadItem(s.data);
            } else if(s.data.data.dataType in Flow.host.dataEditorTypes) {
                var editor = new Flow.Data.Memory.MemoryEditView({model: new Bb.Model(s.data), memory: s.source});
                Flow.tickManager.run(editor);
            }
            else
            {
                alert("got data of type \""+s.data.data.dataType+"\" but there is no editor for it registered!");
            }
        });
    });

    Flow.Data.Memory.MemoryEntityView = Bb.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Data-Memory-MemoryEntityView").html())),
        events: {
            "click #btnCreate": "createItem",
            "click #btnImport": "importItem",
        },
        initialize: function(entity) {
            this.infos = [];

            this.refresh(entity);
            this.render();
            Flow.service.addListenSource("flow.data.memory.OverviewResponse", entity.id);
            Flow.service.addListenSource("flow.data.memory.AddedMsg", entity.id);
            Flow.service.addListenSource("flow.data.memory.UpdateMsg", entity.id);
            Flow.service.addListenSource("flow.data.memory.RemoveMsg", entity.id);
            Flow.service.addListenSource("flow.data.memory.StoreSuccessMsg", entity.id);
            Flow.service.addListenSource("flow.data.memory.StoreFailedMsg", entity.id);
            Flow.service.addListenSource("flow.data.memory.IncompatibleMemory", entity.id);
            Flow.service.addListenSource("flow.data.memory.RemoveFailedMsg", entity.id);
            Flow.service.addListenSource("flow.data.memory.InfoResponse", entity.id);
            Flow.service.addListenSource("flow.data.memory.Response", entity.id);

            Flow.service.send({
                dataType: "flow.data.memory.OverviewRequest"
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
                this.infos[info.id] = new Flow.Data.Memory.MemoryItemView({entity: this.entity, model: info});
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
                dataType: "flow.data.memory.RequestNew",
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
                                dataType: "flow.data.memory.StoreRequest",
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

    Flow.Data.Memory.MemoryItemView = Bb.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Data-Memory-MemoryItemView").html())),
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
                dataType: "flow.data.memory.Request",
                data: {
                    dataType: "flow.data.memory.RequestInfo", 
                    id: this.model.id,
                    revision: parseInt(e.currentTarget.getAttribute("revision"))
                }
            }, this.entity);
        },
        exportItem: function(e) {
            var group = Flow.randomId();
            Flow.Data.Memory.memoryExports[group] = this;

            Flow.service.send({
                dataType: "flow.data.memory.Request",
                group: group,
                data: {
                    dataType: "flow.data.memory.RequestInfo",
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
                dataType: "flow.data.memory.RemoveRequest",
                data: this.model.id
            }, this.entity);
        },
    });

    Flow.Data.Memory.MemoryEditView = Ep.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Data-Memory-MemoryEditView").html())),
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
            var display = _.template(_.unescape($(tpl).filter("#Flow-Data-Memory-MemoryEditView-display").html()))(this.model.attributes);
            return display;
        },
        prepareModel: function() {
            var m = this.model.attributes;
            m.name = m.name || "";
            m.description = m.description || "";
        },
        save: function() {
            var group = Flow.randomId();
            Flow.Data.Memory.memoryEditStoreWaiters[group] = this;
            this.validate();
            if(this.model.isValid) {
                this.model.attributes.data = this.editor.model.attributes;
                Flow.service.send({
                    dataType: "flow.data.memory.StoreRequest",
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