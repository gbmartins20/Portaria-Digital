export type Plant={id:string;name:string;active:boolean;stock:number;version:number};
export const movementNames={production:'Produção',arrival:'Chegada',departure:'Saída',initial:'Saldo inicial'};
export type MovementKind=keyof typeof movementNames;
export const originNames={street:'Trazida da rua',compensation:'Medida compensatória',other:'Outra origem'};
export type Movement={id:string;plant_id:string;plant_name:string;kind:MovementKind;quantity:number;day:string;origin:keyof typeof originNames|'';destination:string;note:string;created_name:string;canceled_at:string|null;cancel_reason:string|null};
export type FlowTotals={production:number;arrival:number;departure:number};
export type GreenhouseData={year:number;plants:Pick<Plant,'id'|'name'|'active'>[];years:number[];stock:number;totals:FlowTotals;monthly:(FlowTotals&{month:number})[];ranking:(FlowTotals&{id:string;name:string})[]};
export const greenhouseToday=()=>new Intl.DateTimeFormat('sv-SE',{timeZone:'America/Sao_Paulo'}).format(new Date());
export const units=(n:number)=>new Intl.NumberFormat('pt-BR').format(n);
export const shortDay=(d:string)=>d.split('-').reverse().join('/');
export function validQuantity(value:string){return /^[1-9][0-9]*$/.test(value)&&Number(value)<=100000000;}
