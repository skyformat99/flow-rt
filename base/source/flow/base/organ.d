module flow.base.organ;

import flow.blocks, flow.interfaces;

mixin template TOrgan(F)
    if(is(F : IData))
{
    import flow.interfaces;

    shared static this()
    {
        Organ.register(fqn!F, (config){
            auto c = config.as!F;
            return new typeof(this)(c);
        });
    }

    @property F tconfig(){return this.context.as!F;}

    this(F config)
    {
        this._config = config;
    }
}

abstract class Organ : IOrgan
{
    private static IOrgan function(IData)[string] _reg;
    
    static void register(string dataType, IOrgan function(IData) creator)
	{
        _reg[dataType] = creator;
	}

	static bool can(IData config)
	{
		return config.dataType in _reg ? true : false;
	}

	static IOrgan create(IData config)
	{
		if(config.dataType in _reg)
			return _reg[config.dataType](config);
		else
			return null;
	}

    private IFlowProcess _process;
    @property IFlowProcess process() {return this._process;}
    @property void process(IFlowProcess value) {this._process = value;}

    protected IData _config;
    @property IData config() {return this._config;}

    protected IData _context;
    @property IData context() {return this._context;}

    void create()
    {
        this._context = this.start();
    }

    void dispose()
    {
        this.stop();
    }

    abstract IData start();
    abstract void stop();

    @property bool finished(){return true;}
}