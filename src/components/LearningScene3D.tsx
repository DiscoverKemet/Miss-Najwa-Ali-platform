import { Canvas, useFrame } from "@react-three/fiber";
import { Environment, Float, Lightformer, RoundedBox } from "@react-three/drei";
import { useRef } from "react";
import type * as THREE from "three";

const blue = "#2563A6";
const navy = "#172554";
const gold = "#F2B84B";
const paper = "#F7FAFC";
const coral = "#E57C68";

function Book({ position, rotation, color }: { position: [number, number, number]; rotation: [number, number, number]; color: string }) {
  return <group position={position} rotation={rotation}>
    <RoundedBox args={[2.5, .34, 1.72]} radius={.1} smoothness={4} castShadow><meshStandardMaterial color={color} roughness={.56}/></RoundedBox>
    <mesh position={[.1, 0, 0]}><boxGeometry args={[2.18, .37, 1.5]}/><meshStandardMaterial color={paper} roughness={.9}/></mesh>
    <mesh position={[-1.22, 0, 0]}><boxGeometry args={[.12, .43, 1.7]}/><meshStandardMaterial color={color} roughness={.58}/></mesh>
  </group>;
}

function Pencil() {
  const pencil = useRef<THREE.Group>(null);
  useFrame(({clock}) => { if (pencil.current) pencil.current.rotation.z = -.28 + Math.sin(clock.elapsedTime * .7) * .04 });
  return <group ref={pencil} position={[-2.5, 1.6, .3]} rotation={[.2, .3, -.28]}>
    <mesh castShadow><cylinderGeometry args={[.16, .16, 3.5, 6]}/><meshStandardMaterial color={gold} roughness={.5}/></mesh>
    <mesh position={[0, 1.9, 0]} castShadow><coneGeometry args={[.16, .42, 6]}/><meshStandardMaterial color={navy}/></mesh>
    <mesh position={[0, -1.88, 0]} castShadow><cylinderGeometry args={[.17, .17, .28, 6]}/><meshStandardMaterial color={coral}/></mesh>
  </group>;
}

function LearningObjects() {
  const group = useRef<THREE.Group>(null);
  useFrame(({clock}, delta) => { if (group.current) { group.current.rotation.y += delta * .045; group.current.position.y = Math.sin(clock.elapsedTime * .5) * .08 } });
  return <group ref={group} position={[.65, -.5, 0]} rotation={[.05, -.25, 0]}>
    <Book position={[0, -1.3, 0]} rotation={[0, -.12, .02]} color={navy}/>
    <Book position={[.18, -.86, .05]} rotation={[0, .12, -.04]} color={blue}/>
    <Book position={[.08, -.42, .04]} rotation={[0, -.04, .03]} color={gold}/>
    <Pencil/>
    <Float speed={1.2} rotationIntensity={.18} floatIntensity={.5}><mesh position={[2.2, 1.55, -.2]} castShadow><octahedronGeometry args={[.48, 0]}/><meshStandardMaterial color={gold} roughness={.35} metalness={.12}/></mesh></Float>
    <Float speed={1.45} rotationIntensity={.16} floatIntensity={.4}><mesh position={[1.05, 2.25, -.7]} castShadow><sphereGeometry args={[.28, 28, 28]}/><meshStandardMaterial color={coral}/></mesh></Float>
    <Float speed={1.05} rotationIntensity={.15} floatIntensity={.35}><mesh position={[-1.5, 2.4, -.3]} castShadow><torusGeometry args={[.42, .12, 16, 42]}/><meshStandardMaterial color={blue}/></mesh></Float>
  </group>;
}

export function LearningScene3D() {
  return <div className="learning-scene" aria-hidden="true"><Canvas shadows dpr={[1, 1.5]} camera={{position:[0, 1.3, 8.7], fov:38}} gl={{antialias:true, alpha:true}}>
    <ambientLight intensity={.75}/><hemisphereLight args={[paper, navy, 1.4]}/>
    <directionalLight position={[4, 7, 5]} intensity={2.3} color={paper} castShadow shadow-mapSize={[1024,1024]}/>
    <pointLight position={[-4,2,3]} intensity={15} distance={10} color={gold}/><LearningObjects/>
    <Environment><Lightformer intensity={2} position={[0,5,1]} scale={[10,8,1]}/><Lightformer intensity={1.4} color={gold} position={[-5,1,0]} rotation-y={Math.PI/2} scale={[10,2,1]}/></Environment>
  </Canvas></div>;
}