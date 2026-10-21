'use strict';
const assert=require('node:assert/strict');
const {StartupController}=require('../startup/controller.cjs');
function harness(){
 let clock=1000,frame={apps:[],frontmostPid:10,inputIdleMs:10000,inputStamp:'idle'};
 const events=[];let quits=0;
 const adapter={snapshot:async()=>frame,record:async(event,details)=>events.push({event,details}),portInUse:async()=>false,quit:async()=>{quits++;return {accepted:false,reason:'test-no-os-actions'};},launch:async()=>{throw Error('Tests must never launch applications');}};
 const controller=new StartupController(adapter,{now:()=>clock,sleep:async()=>{}});
 return {controller,adapter,events,setFrame:v=>frame=v,setTime:v=>clock=v,get quits(){return quits;}};
}
function app(extra={}){return {pid:10,key:'app-10',launchedAt:900,argumentsKnown:true,plainLaunch:true,debugPort:null,finishedLaunching:true,...extra};}
function frame(a,extra={}){return {apps:[a],frontmostPid:10,inputIdleMs:10000,inputStamp:'idle',...extra};}
async function main(){
 let passed=0;
 let h=harness();await h.controller.tick();h.setFrame(frame(app({argumentsKnown:false})));await h.controller.tick();assert.equal(h.controller.pendingLaunch,true);assert.equal(h.quits,0);h.setTime(1200);h.setFrame(frame(app()));await h.controller.tick();assert.equal(h.quits,1,'transient unknown args no longer permanently skip fresh app');passed++;
 h=harness();h.setFrame(frame(app()));await h.controller.tick();await h.controller.tick();assert.equal(h.quits,0,'existing active app never taken over');passed++;
 h=harness();await h.controller.tick();h.setTime(10000);h.setFrame(frame(app({launchedAt:0,argumentsKnown:false})));await h.controller.tick();assert.equal(h.quits,0);assert.equal(h.events.at(-1).event,'skipped-unknown-arguments');passed++;
 h=harness();await h.controller.tick();h.setFrame(frame(app({plainLaunch:false})));await h.controller.tick();assert.equal(h.quits,0);assert.equal(h.events.at(-1).event,'skipped-launch-arguments');passed++;
 h=harness();await h.controller.tick();h.setFrame(frame(app({debugPort:'39222'})));await h.controller.tick();assert.equal(h.quits,0);assert.equal(h.events.at(-1).event,'already-debug-enabled');passed++;
 h=harness();await h.controller.tick();h.setFrame(frame(app(),{inputIdleMs:10}));await h.controller.tick();assert.equal(h.quits,0);assert.equal(h.events.at(-1).event,'skipped-active-or-background');passed++;
 h=harness();await h.controller.tick();h.setFrame(frame(app(),{frontmostPid:99}));await h.controller.tick();assert.equal(h.quits,0);assert.equal(h.controller.pendingLaunch,true);passed++;
 h=harness();await h.controller.tick();h.adapter.portInUse=async()=>true;h.setFrame(frame(app()));await h.controller.tick();assert.equal(h.quits,0);assert.equal(h.events.at(-1).event,'port-in-use');passed++;
 h=harness();await h.controller.tick();h.controller.lastAttemptAt=950;h.setFrame(frame(app()));await h.controller.tick();assert.equal(h.quits,0);assert.equal(h.events.at(-1).event,'skipped-cooldown');passed++;
 h=harness();await h.controller.tick();h.setFrame({...frame(app()),apps:[app(),app({pid:11,key:'app-11'})]});await h.controller.tick();assert.equal(h.quits,0);assert.equal(h.events.at(-1).event,'skipped-multiple-instances');passed++;
 h=harness();await h.controller.tick();h.setFrame({...frame(app()),apps:[app(),app({pid:11,key:'app-11',argumentsKnown:false})]});await h.controller.tick();assert.equal(h.controller.pendingLaunch,true);assert.equal(h.quits,0);h.setTime(10000);await h.controller.tick();assert.equal(h.quits,0);assert.equal(h.events.at(-1).event,'skipped-multiple-instances');passed++;
 console.log(JSON.stringify({passed,realProcessActions:0,activeWindowAndInputProtectionsPreserved:true}));
}
main().catch(e=>{console.error(e);process.exitCode=1;});
