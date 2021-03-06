package component;

class Collectable extends Component {
	public var collisionGroups:Array<component.Collisions.CollisionGroup>;
	public var items:Array<component.Inventory.Item> = [];
	public function new (?collisionGroups:Array<component.Collisions.CollisionGroup>,items:Array<component.Inventory.Item>){
		this.collisionGroups = collisionGroups;
		if (collisionGroups == null)
			this.collisionGroups = component.Collisions.CollisionGroup.createAll();//[];

		this.items = items;
		
		super();
	}
}