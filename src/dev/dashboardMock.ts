import type {DashboardData} from '../Dashboard';
export function dashboardMock(f:Record<string,string>):DashboardData{
 const monthly=[2025,2026].flatMap(y=>[1,2,10].map((m,i)=>({label:`${y}-${String(m).padStart(2,'0')}`,records:20*(i+1),people:50*(i+1),volume:100*(i+1)}))).filter(x=>(!f.from||x.label+'-15'>=f.from)&&(!f.to||x.label+'-15'<=f.to));
 const n=monthly.reduce((s,x)=>s+x.records/20,0);
 return {years:[2026,2025],totals:{records:20*n,people:50*n,companions:30*n,volume:100*n,unknown_quantity:n,cities:n?2:0},undated:0,monthly,ages:n?[{label:'5-15',value:10*n},{label:'21-35',value:20*n},{label:'36-59',value:20*n}]:[],sex:n?[{label:'Masculino',value:30*n},{label:'Feminino',value:20*n}]:[],cities:n?[{label:'CIDADE DE TESTE A',value:30*n},{label:'CIDADE DE TESTE B',value:20*n}]:[],types:n?[{label:'TIPO DE TESTE A',records:12*n,volume:60*n},{label:'TIPO DE TESTE B',records:8*n,volume:40*n}]:[],companies:n?[{label:'EMPRESA DE TESTE A',records:14*n,volume:70*n},{label:'EMPRESA DE TESTE B',records:6*n,volume:30*n}]:[]};
}
