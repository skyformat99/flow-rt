module flow.example.base.trainingkicker.signals;

import flow.base.blocks, flow.base.data;

class Whisper : Unicast{mixin signal!(EntityPtr);}
class BallKicked : Multicast{mixin signal!();}
class StopKicking : Multicast{mixin signal!();}
class ReturnBall : Anycast{mixin signal!();}
