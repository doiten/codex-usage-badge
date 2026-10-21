'use strict';
const assert=require('node:assert/strict');
const vm=require('node:vm');
const {installUsageBadge}=require('../agent.cjs');
const source=installUsageBadge.toString();
const match=source.match(/  function findSafeTop\([^]*?^  }/m);
assert.ok(match,'self-contained geometry helper exists');
const safe=vm.runInNewContext('('+match[0]+')');
const cases=[
 ['empty rail preserves requested top',300,50,500,84,[],300],
 ['top viewport clamp',-100,50,500,84,[],50],
 ['bottom viewport clamp',1000,50,500,84,[],416],
 ['reserve native controls and six pixel clearance',416,50,500,84,[{top:50,bottom:110},{top:440,bottom:500}],350],
 ['new update button forces nearest free interval',245,50,500,84,[{top:50,bottom:110},{top:250,bottom:286},{top:440,bottom:500}],292],
 ['overlapping native controls merge',120,0,300,40,[{top:60,bottom:110},{top:90,bottom:140}],146],
 ['exact-fit empty interval remains usable',100,50,300,84,[{top:50,bottom:100},{top:196,bottom:210}],106],
 ['short window clamps saved preference',400,50,260,84,[{top:50,bottom:86},{top:225,bottom:260}],135],
 ['space shortage hides badge instead of covering native controls',120,50,200,84,[{top:50,bottom:86},{top:164,bottom:200}],null],
 ['window smaller than badge',0,8,70,84,[],null],
 ['fully blocked rail',100,0,300,84,[{top:0,bottom:300}],null],
 ['dual quota meters need their full height',400,50,300,144,[{top:50,bottom:86},{top:265,bottom:300}],115],
 ['invalid stored geometry is rejected',NaN,0,300,84,[],null],
 ['out-of-range controls do not consume empty space',100,50,300,84,[{top:-100,bottom:-50},{top:400,bottom:500}],100]
];
for(const [name,desired,top,bottom,height,obstacles,expected] of cases){
 const actual=safe(desired,top,bottom,height,obstacles);
 assert.equal(actual,expected,name);
 if(actual!==null){
  assert.ok(actual>=top&&actual+height<=bottom,name+' remains in viewport');
  for(const r of obstacles)assert.ok(actual+height<=r.top-6||actual>=r.bottom+6,name+' avoids native controls');
 }
}
assert.equal(safe(400,50,260,84,[{top:50,bottom:86},{top:225,bottom:260}]),135);
assert.equal(safe(400,50,912,84,[{top:50,bottom:86},{top:876,bottom:912}]),400,'larger window restores requested preference');
console.log('PASS 16 quota placement geometry cases: clamps, native controls, dual-ring height, insufficient space and restored preference');
