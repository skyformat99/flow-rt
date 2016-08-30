module flow.example.base.trainingkicker.signals;

import flow.blocks, flow.data;

class Whisper : Unicast{mixin signal!(EntityRef);}
class BallKicked : Multicast{mixin signal!();}
class StopKicking : Multicast{mixin signal!();}
class ReturnBall : Anycast{mixin signal!();}
