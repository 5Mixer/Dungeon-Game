package;

import kha.Framebuffer;
import kha.Scheduler;

typedef Dungeon = {
	var seed:Int;
}
typedef PlayerSave = {
	var pos : {x: Int, y:Int};
	var health: Int;
	var inventory: Array<component.Inventory.Stack>;
}
typedef Save  = {
	var player : PlayerSave;
	var dungeonLevel: Int;
	var dungeons:Array<Dungeon>;
}

class Project {
	public var camera:Camera;
	var frame = 0;
	var input:Input;

	var lastTime:Float;
	var realLastTime:Float;
	var lastRenderTime:Float;
	public var entities:eskimo.EntityManager;

	var systems:eskimo.systems.SystemManager;
	var renderSystems = new Array<System>();
	var renderview:eskimo.views.View;
	
	var p:eskimo.Entity;

	var minimap:kha.Image;
	var minimapOpacity = 1.0;
	
	public static var spriteData = CompileTime.parseJsonFile('../assets/spriteData.json');
	
	var dungeonLevel = 1;

	var overlay:Float = 0.0;

	var lastSave:Save;
	var dungeons:Array<Dungeon> = [];
	
	var debugInterface:ui.DebugInterface;

	var states:Array<states.State> = [];

	public function new() {
		kha.System.notifyOnRender(render);
		Scheduler.addTimeTask(update, 0, 1 / 60);
		
		input = new Input();
		camera = new Camera();
		kha.input.Mouse.get().hideSystemCursor();

		var components = new eskimo.ComponentManager();
		entities = new eskimo.EntityManager(components);
		systems = new eskimo.systems.SystemManager(entities);		

		registerRenderSystem(new system.TilemapRenderer(camera,entities));
		registerRenderSystem(new system.Renderer(entities));
		registerRenderSystem(new system.SpikeHandler(entities));
		registerRenderSystem(new system.ParticleRenderer(entities));
		registerRenderSystem(new system.DebugView(entities));
		registerRenderSystem(new system.Healthbars(entities));
		
		var collisionSys = new system.Collisions(entities);
		registerRenderSystem(new system.CollisionDebugView(entities,collisionSys.grid,true));
		
		systems.add(collisionSys);
		systems.add(new system.KeyMovement(input,entities));
		systems.add(new system.Physics(entities,collisionSys.grid,collisionSys));
		systems.add(new system.Inventory(input,entities));
		systems.add(new system.TimedLife(entities));
		systems.add(new system.TimedLife(entities));
		systems.add(new system.Gun(input,camera,entities));
		systems.add(new system.AI(entities,null));
		systems.add(new system.Magnets(entities,p));
		systems.add(new system.GrappleHooker(input,camera,entities,collisionSys));
		
		createMap();

		lastTime = Scheduler.time();
		realLastTime = Scheduler.realTime();
		lastRenderTime = Scheduler.time();

		debugInterface = new ui.DebugInterface();
		
		input.listenToKeyRelease('r', descend);
		input.listenToKeyRelease('q',function (){
			debugInterface.visible = !debugInterface.visible;
		});
		input.listenToKeyRelease('m', function (){
			minimapOpacity = 1.0;
		});
		input.wheelListeners.push(function(dir){
			if (p.get(component.Inventory) == null) return;
			p.get(component.Inventory).activeIndex += dir;
			if (p.get(component.Inventory).activeIndex < 0) p.get(component.Inventory).activeIndex = p.get(component.Inventory).length-1;
			if (p.get(component.Inventory).activeIndex > p.get(component.Inventory).length-1) p.get(component.Inventory).activeIndex = 0;
		});
		
	}
	function registerRenderSystem(system:System){
		renderSystems.push(system);
		systems.add(system);
	}
	function createMap () {
		entities.clear();
		
		(cast systems.get(system.Collisions)).processFixedEntities = true;
		var map = entities.create();
		map.set(new component.Transformation(new kha.math.Vector2())); 
		map.set(new component.Tilemap());
		map.set(new component.Collisions([component.Collisions.CollisionGroup.Level],[]));
		map.get(component.Collisions).fixed = true;
		(cast systems.get(system.AI)).map = map.get(component.Tilemap);


		var generator = new util.DungeonWorldGenerator(60,60);
		map.get(component.Tilemap).tiles = generator.tiles;
		map.get(component.Tilemap).width = 60;
		map.get(component.Tilemap).height = 60;
		
		minimap = kha.Image.createRenderTarget(60,60);
		
		minimapOpacity = 1.0;
		minimap.g2.begin();
		minimap.g2.clear(kha.Color.fromBytes(0,0,0,200));
		var t = 0;
		var collisionRects = [];
		while (t < generator.tiles.length-1){
			var tile = generator.tiles[t];
			if (map.get(component.Tilemap).tileInfo.get(tile).collide){
				var x = t%map.get(component.Tilemap).width;
				var y = Math.floor(t/map.get(component.Tilemap).width);
				var width = 1;
				var height = 1;
				/*while (map.get(component.Tilemap).tileInfo.get(generator.tiles[t+width]).collide && Math.floor((t+width)/map.get(component.Tilemap).width) == y){
				
					width += 1;
				}*/
				
				collisionRects.push({x:x,y:y,width:width,height:height,resolved:false,t:t});

				t += width;

				minimap.g2.color = map.get(component.Tilemap).tileInfo.get(tile).colour;
				minimap.g2.fillRect(t%map.get(component.Tilemap).width,Math.floor(t/map.get(component.Tilemap).width),1,1);
				
			}else{
				t+=1;
			}
		}
		for (rect in collisionRects){
			if (rect.resolved) continue;
			var width = 1;
			/*while (generator.tiles[rect.t+width] != null && map.get(component.Tilemap).tileInfo.get(generator.tiles[rect.t+width]).collide && Math.floor((rect.t+width)/map.get(component.Tilemap).width) == rect.y){
				width += 1;
				collisionRects[rect.t+width].resolved=true;
				rect.resolved = true;
			}*/
			map.get(component.Collisions).registerCollisionRegion(new component.Collisions.Rect(
					rect.x*16,rect.y*16,
					width*16,rect.height*16));
		}

		minimap.g2.color = kha.Color.Red;
		minimap.g2.fillRect(generator.spawnPoint.x,generator.spawnPoint.y,1,1);

		minimap.g2.color = kha.Color.Green;
		minimap.g2.fillRect(generator.exitPoint.x,generator.exitPoint.y,1,1);
		minimap.g2.end();
		
		for (t in generator.treasure){
			EntityFactory.createTreasure(entities,t.x*16,t.y*16);
		}
		for (e in generator.enemies){
			EntityFactory.createSlime(entities,e.x*16,e.y*16);
			EntityFactory.createGoblin(entities,e.x*16,e.y*16);
		}
		for (s in generator.spikes){
			EntityFactory.createSpike(entities,s.x*16,s.y*16);
		}

		EntityFactory.createLadder(entities,generator.exitPoint.x*16,generator.exitPoint.y*16,descend);

		p = EntityFactory.createPlayer(entities,{x:generator.spawnPoint.x, y:generator.spawnPoint.y});
		p.get(component.Inventory).putIntoInventory(component.Inventory.Item.SlimeGun);
		p.get(component.Events).listenToEvent(component.Events.Event.Death,function (args){
			states.push(new states.Dead());
		});
		if (lastSave != null && lastSave.player != null){
			p.get(component.Health).current = lastSave.player.health;
			p.get(component.Inventory).stacks = lastSave.player.inventory;
		}

		dungeons.push ({
			seed: generator.seed
		});

		return map;
	}
	function descend (){
		states = [];
		overlay = .7;
		dungeonLevel++;
		save();
		createMap();
		save();
	}
	
	function save (){
		lastSave = {
			dungeonLevel: dungeonLevel,
			dungeons: dungeons,
			player: null
		};
		if (p.get(component.Transformation) != null)
			lastSave.player = {
				pos: {
					x: Math.round(p.get(component.Transformation).pos.x),
					y: Math.round(p.get(component.Transformation).pos.y)
				},
				health: Math.round(p.get(component.Health).current),
				inventory: p.get(component.Inventory).stacks
			}
		
	}

	function update() {
		input.startUpdate();
		
		var delta = Scheduler.time() - lastTime;
		var realDelta = Scheduler.realTime() - realLastTime;

		if (p.get(component.Inventory) != null){
			var pinv = p.get(component.Inventory);
			var selectedItem = pinv.getByIndex(pinv.activeIndex).item;
			var itemData = pinv.itemData.get(selectedItem);
			if (selectedItem == component.Inventory.Item.SlimeGun){
				p.get(component.Gun).gun = component.Gun.GunType.SlimeGun;
				p.get(component.Gun).fireRate = 7;
			}else if (selectedItem == component.Inventory.Item.LaserGun) {
				p.get(component.Gun).gun = component.Gun.GunType.LaserGun;
				p.get(component.Gun).fireRate = 4;
			}else{
				p.get(component.Gun).gun = null;

			}
		}
		
		if (minimapOpacity > 0)
			if (minimapOpacity - delta < 0)
				minimapOpacity = 0;
			else
				minimapOpacity -= delta;

		systems.update(delta);
		cast(systems.get(system.Physics),system.Physics).grid = cast(systems.get(system.Collisions),system.Collisions).grid;
		cast(systems.get(system.Magnets),system.Magnets).p = p;

		if (p != null && p.has(component.Transformation))
			camera.pos = new kha.math.Vector2(p.get(component.Transformation).pos.x-kha.System.windowWidth()/2/camera.scale.x,p.get(component.Transformation).pos.y-kha.System.windowHeight()/2/camera.scale.y);
		
		debugInterface.fpsGraph.pushValue(1/delta/debugInterface.fpsGraph.size.y);
		
		if (overlay > 0.0) overlay -= delta;
		if (overlay < 0.0) overlay = 0.0;

		lastTime = Scheduler.time();
		realLastTime = Scheduler.realTime();

		cast(systems.get(system.CollisionDebugView),system.CollisionDebugView).showActiveEntities = (debugInterface.activeCollisionRegionsShown);
		cast(systems.get(system.CollisionDebugView),system.CollisionDebugView).showStaticEntities = (debugInterface.staticCollisionRegionsShown);
		
		
		for (state in states)
			state.update(delta);

		input.endUpdate();
	}
	function render(framebuffer: Framebuffer): Void {
		frame++;

		var renderDelta = Scheduler.time() - lastRenderTime;

		var g = framebuffer.g2;
		g.begin();
		g.color = kha.Color.White;
		
		camera.transform(g);

		for (system in renderSystems)
			system.render(g);

		var transformation = p.get(component.Transformation);
		var collisions = p.get(component.Collisions);
		var pinv = p.get(component.Inventory);
		if (transformation != null){
			if (pinv.getByIndex(pinv.activeIndex).item == component.Inventory.Item.GrapplingHook){
				var collisionSystem:system.Collisions = cast systems.get(system.Collisions);
				var dir = transformation.pos.sub(camera.screenToWorld(input.mousePos.sub(new kha.math.Vector2(24,24))));
				var a = Math.atan2(-dir.y,-dir.x)*(180/Math.PI);
				var endx = Math.cos(a*(Math.PI/180))*200;
				var endy = Math.sin(a*(Math.PI/180))*200;
				var px = transformation.pos.x + collisions.midpoint.x;
				var py = transformation.pos.y + collisions.midpoint.y;
				var l = collisionSystem.fireRay(new differ.shapes.Ray(new differ.math.Vector(px,py),new differ.math.Vector(px+endx,py+endy)),[component.Collisions.CollisionGroup.Player]);
				g.drawLine(px,py,px+endx*l,py+endy*l);
				var rayDist = l * Math.sqrt(Math.pow(endx,2)+Math.pow(endy,2));
				
				var hookLength = 8;
				var hooks = Math.floor(rayDist/hookLength);
				
				//Refer to kha2d for rotating sprite help
				g.pushTransformation(g.transformation.multmat(kha.math.FastMatrix3.translation(px, py)).multmat(kha.math.FastMatrix3.rotation(a*(Math.PI/180))).multmat(kha.math.FastMatrix3.translation(-px - collisions.midpoint.x, -py - collisions.midpoint.y+1)));
				for (i in 0...hooks){
					g.drawSubImage(kha.Assets.images.Objects,px+(i*hookLength),py,6*8,0,8,8);
				}
				var clawx:Float = px+(hooks*hookLength);
				//Extra half a chain
				if (rayDist%hookLength > .5*hookLength){
					clawx += hookLength/2;
					g.drawSubImage(kha.Assets.images.Objects,px+((hooks)*hookLength),py,6*8,0,4,8);

				}
				//Final claw
				g.drawSubImage(kha.Assets.images.Objects,clawx,py,7*8,0,8,8);
				g.popTransformation();

			}
		}
		
		camera.restore(g);
		
		//Draw mouse cursor.
		if (debugInterface.visible){
			kha.input.Mouse.get().showSystemCursor();
			input.mouseEvents = false;
		}else{
			input.mouseEvents = true;
			kha.input.Mouse.get().hideSystemCursor();
			g.color = kha.Color.White;
			g.drawSubImage(kha.Assets.images.Entities,input.mousePos.x/4 -8,input.mousePos.y/4 -8,2*16,0,16,16);
		}

		//Clear any transformation for the UI.
		g.pushTransformation(kha.math.FastMatrix3.identity());
		g.transformation._00 = 5;
		g.transformation._11 = 5;
		g.transformation._20 = kha.System.windowWidth()/2 - minimap.width*5/2;
		g.transformation._21 = kha.System.windowHeight()/2 - minimap.height*5/2;
		g.color = kha.Color.fromFloats(1,1,1,minimapOpacity);
		g.drawImage(minimap,0,0);

		g.transformation = kha.math.FastMatrix3.identity();
		
		var x = 0;
		g.color = kha.Color.White;
		g.font = kha.Assets.fonts.trenco;
		g.fontSize = 38;

		var pinv = p.get(component.Inventory);
		g.color = kha.Color.fromBytes(234,211,220);

		if (p.has(component.Inventory)){
			g.drawString(pinv.itemData.get(pinv.getByIndex(pinv.activeIndex).item).name,(3*4), -1*4);
			
			g.translate(0,8*4);
			for (stack in p.get(component.Inventory).stacks){
				g.transformation._00 = camera.scale.x;
				g.transformation._11 = camera.scale.y;
				system.Renderer.renderSpriteData(g,p.get(component.Inventory).itemData.get(stack.item).sprite,6,x*10);
				
				g.color = kha.Color.fromBytes(112,107,137);
				if (x == pinv.activeIndex)
					g.fillRect(1,x*10+1,1,6);

				g.transformation._00 = 1;
				g.transformation._11 = 1;
				g.color = kha.Color.fromBytes(234,211,220);
				g.drawString(stack.quantity+"",(3*4), (x*10*4)-8);
				
				x++;
				
			}
		}

		g.transformation = kha.math.FastMatrix3.identity();
		g.font = kha.Assets.fonts.OpenSans;
		g.color = kha.Color.White;
		g.fontSize = 20;
		g.drawString("Floor "+dungeonLevel,10,kha.System.windowHeight()-30);

		g.transformation = kha.math.FastMatrix3.identity();

		g.color = kha.Color.fromFloats(0,0,0,overlay);
		g.fillRect(0,0,kha.System.windowWidth(),kha.System.windowHeight());

		g.color = kha.Color.White;

		g.popTransformation();
		
		g.end();
		debugInterface.render(g);

		debugInterface.updateGraph.pushValue(1/renderDelta/debugInterface.updateGraph.size.y);

		g.transformation = kha.math.FastMatrix3.identity();

		for (state in states)
			state.render(framebuffer);
		

		lastRenderTime = Scheduler.time();
	}
}
