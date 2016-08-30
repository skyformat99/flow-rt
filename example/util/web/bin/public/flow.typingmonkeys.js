define("flow.typingmonkeys", ["flow", "backbone", "underscore", "text!flow.typingmonkeys.html"], function(Flow, Bb, _, tpl){
    var Flow = Flow || {};
    Flow.Example = Flow.Example || {};
    Flow.Example.TypingMonkeys = Flow.Example.TypingMonkeys || {};
    
    Flow.Example.CommunicatingOverseerView = Bb.View.extend({
        template: _.template(_.unescape($(tpl).filter("#Flow-Example-CommunicatingOverseerView").html())),
        events: {
            "click #Flow-Example-CommunicatingOverseerView-btnSearch": "search",
        },
        initialize: function(entity) {
            this.entity = entity;
            this.render();
            Flow.service.addListenSource("flow.example.util.web.main.OverseerFound", entity.id);
        },
        destroy: function() {
            this.remove();
            this.unbind();
            //this.entity.unbind("change", this.modelChanged);
            //for(i in this.entityViews)
            //    this.entityViews[i].destroy();
        },
        render: function() {
            this.$el.html(this.template(this.entity));
            return this;
        },
        search: function() {
            var s = {
                dataType: "flow.example.util.web.main.OverseerSearch",
                data: {
                    dataType: "flow.example.util.web.main.OverseerSearchData",
                    search: "!!"
                }
            };
            Flow.service.send(s, this.entity);
        },
        found: function(s) {
            this.giveCandy(s.data.author);
        },
        giveCandy: function(monkey) {
            var s = {
                dataType: "flow.example.util.web.main.OverseerGiveCandy",
                data: monkey
            };
            Flow.service.send(s, this.entity);
        }
    });

    // registering signals
    Flow.service.registerInit(function() {    
        // registering views for entities
        Flow.tick.overview.register("flow.example.util.web.main.CommunicatingOverseer", Flow.Example.CommunicatingOverseerView);

        Flow.service.beginListen("flow.example.util.web.main.OverseerFound", function(s) {
            if(s.source.id in Flow.tick.overview.entityViews) {
                var view = Flow.tick.overview.entityViews[s.source.id];
                view.found(s);
            }
        });
    });
});