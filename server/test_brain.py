import unittest,tempfile,time,json,io,urllib.error,urllib.request,threading
from unittest.mock import patch
from pathlib import Path
from vigil_brain import BrainRouter,Failure,DeviceRegistry,digest,enrol_device,NeuralSpeech,macy_prompt,make_server,free_route

def candidate(provider,model,vision=True):
 hosts={'opencode-go':'opencode.ai','openrouter':'openrouter.ai','nvidia':'integrate.api.nvidia.com'}
 return dict(provider=provider,model=model,vision=vision,endpoint='https://'+hosts[provider]+'/v1/chat/completions',protocol='chat')

class BrainTests(unittest.TestCase):
 def test_existing_friend_edition_keeps_free_focus_and_its_route_restrictions(self):
  with tempfile.TemporaryDirectory() as folder:
   private=Path(folder);registry=DeviceRegistry(private/'devices.json')
   registry.state['tokens'][digest('synthetic-friend')]={'edition':'friend'}
   flags=[]
   class Router:
    def complete(self,prompt,**kwargs):flags.append(kwargs);return {'text':'Synthetic answer.'}
   class Speech:
    def render(self,*args):raise AssertionError('Friend speech must remain forbidden')
   server=make_server(private,registry,Speech(),Router(),port=0,monitor_models=False)
   thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
   def post(route,data):
    request=urllib.request.Request('http://127.0.0.1:'+str(server.server_port)+route,data=json.dumps(data).encode(),headers={'Authorization':'Bearer synthetic-friend','Content-Type':'application/json'})
    return urllib.request.urlopen(request,timeout=5)
   try:
    with post('/answer',{'text':'Synthetic focus','purpose':'focus'}) as response:self.assertEqual(response.status,200)
    self.assertEqual(flags,[{'free_only':True}])
    for route,data in [('/answer',{'text':'Synthetic question','purpose':'question'}),('/speech',{'text':'Synthetic speech'})]:
     with self.assertRaises(urllib.error.HTTPError) as error:post(route,data)
     self.assertEqual(error.exception.code,403)
   finally:server.shutdown();server.server_close();thread.join(timeout=5)
 def test_production_model_filter_excludes_paid_and_stopped_routes_before_probing(self):
  for provider,model in [('opencode-go','subscription'),('openrouter','vendor/paid'),('openrouter','anthropic/claude:free'),('nvidia','openai/gpt-oss')]:
   self.assertFalse(free_route({'provider':provider,'model':model}))
  for provider,model in [('nvidia','nemotron'),('ollama-cloud','gemma4:31b'),('openrouter','nemotron:free'),('opencode','fixture-free')]:
   self.assertTrue(free_route({'provider':provider,'model':model}))
 def test_authenticated_macy_http_answers_and_speech_without_weakening_auth(self):
  with tempfile.TemporaryDirectory() as folder:
   private=Path(folder);registry=DeviceRegistry(private/'devices.json')
   registry.state['tokens'][digest('synthetic-macy')]={'edition':'macy'}
   registry.state['tokens'][digest('synthetic-keith')]={'edition':'keith'}
   prompts=[];languages=[]
   class Router:
    def complete(self,prompt):prompts.append(prompt);return {'text':'Synthetic answer.','local':False,'provider':'fixture','model':'fixture'}
   class Speech:
    def render(self,text,language):languages.append(language);return b'RIFF'+b'0'*100
   server=make_server(private,registry,Speech(),Router(),port=0,monitor_models=False)
   thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
   def post(route,token,data):
    request=urllib.request.Request('http://127.0.0.1:'+str(server.server_port)+route,data=json.dumps(data).encode(),headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
    return urllib.request.urlopen(request,timeout=5)
   try:
    for route in ['/answer','/speech']:
     with self.assertRaises(urllib.error.HTTPError) as error:post(route,'untrusted',{'text':'Synthetic'})
     self.assertEqual(error.exception.code,401)
    with post('/answer','synthetic-macy',{'text':'Synthetic','purpose':'focus'}) as response:self.assertEqual(response.status,200)
    self.assertEqual(prompts[-1]['purpose'],'question');self.assertIn('US English',prompts[-1]['system'])
    with post('/speech','synthetic-macy',{'text':'Synthetic'}) as response:self.assertTrue(response.read().startswith(b'RIFF'))
    self.assertEqual(languages[-1],'en-US')
    with post('/answer','synthetic-keith',{'text':'Synthetic','purpose':'focus'}) as response:self.assertEqual(response.status,200)
    self.assertEqual(prompts[-1]['purpose'],'focus')
    with post('/speech','synthetic-keith',{'text':'Synthetic'}) as response:self.assertEqual(response.status,200)
    self.assertEqual(languages[-1],'en-GB')
   finally:server.shutdown();server.server_close();thread.join(timeout=5)
 def test_macy_focus_uses_free_failover_and_us_english_without_mutating_request(self):
  source={'text':'Task: synthetic focus','system':'Return classification JSON.','purpose':'focus','edition':'keith'}
  prompt=macy_prompt(source)
  self.assertEqual(source['purpose'],'focus')
  self.assertEqual(prompt['purpose'],'question')
  self.assertTrue(prompt['system'].endswith('Use US English.'))
  calls=[]
  models=[candidate('opencode-go','subscription'),candidate('openrouter','paid'),candidate('openrouter','one:free'),candidate('nvidia','two')]
  def transport(model,*args):
   calls.append(model['model'])
   if model['model']=='one:free':raise Failure('429',time.time()+60)
   return '{"choice":"on_task","p_on":1,"p_off":0,"p_uncertain":0}'
  router=BrainRouter(models,{m['provider']:'synthetic' for m in models},transport)
  for i,model in enumerate(models):router.health[router.id(model)].update(status='green',latency=i)
  self.assertEqual(router.complete(prompt)['provider'],'nvidia')
  self.assertEqual(calls,['one:free','two'])
 def test_macy_us_speech_cache_is_separate_and_untrusted_locale_rejected(self):
  with tempfile.TemporaryDirectory() as folder:
   speech=NeuralSpeech(Path(folder));text='Synthetic speech.'
   us=speech.cache/(digest('piper-ljspeech-v1:'+text)+'.wav');us.write_bytes(b'RIFF'+b'U'*100)
   gb=speech.cache/(digest('piper-alan-v1:'+text)+'.wav');gb.write_bytes(b'RIFF'+b'B'*100)
   with patch('vigil_brain.subprocess.run') as run:
    self.assertEqual(speech.render(text,'en-US'),us.read_bytes())
    self.assertEqual(speech.render(text),gb.read_bytes());run.assert_not_called()
   with self.assertRaises(ValueError):speech.render(text,'../../untrusted')
 def test_neural_cache_reuses_audio_without_synthesis_and_has_bounded_names(self):
  with tempfile.TemporaryDirectory() as folder:
   speech=NeuralSpeech(Path(folder));text='Synthetic speech.'
   path=speech.cache/(digest('piper-alan-v1:'+text)+'.wav')
   path.write_bytes(b'RIFF'+b'0'*100)
   with patch('vigil_brain.subprocess.run') as run:
    self.assertEqual(speech.render(text),path.read_bytes());run.assert_not_called()
   self.assertNotIn(text,path.name)
 def test_neural_rejects_invalid_text_and_parallel_synthesis(self):
  with tempfile.TemporaryDirectory() as folder:
   speech=NeuralSpeech(Path(folder))
   for text in ['',None,123,'x'*301]:
    with self.assertRaises(ValueError):speech.render(text)
   speech.gate.acquire()
   with self.assertRaises(RuntimeError):speech.render('Synthetic')
   speech.gate.release()
 def setUp(self):
  self.models=[candidate('opencode-go','a'),candidate('openrouter','b:free'),candidate('nvidia','c')]
  self.keys={m['provider']:'synthetic' for m in self.models}
 def test_go_request_matches_opencode_and_keeps_credentials_out_of_url(self):
  m=candidate('opencode-go','glm-5.3-flash',False)
  m['endpoint']='https://opencode.ai/inference/go/openai/v1/chat/completions'
  router=BrainRouter([m],{'opencode-go':'synthetic-go','_opencode-go-org-id':'synthetic-org'})
  with patch('vigil_brain.urllib.request.urlopen') as send:
   send.return_value.__enter__.return_value=io.StringIO(json.dumps({'choices':[{'message':{'content':'ok'}}]}))
   self.assertEqual(router.http(m,{'text':'synthetic'},5),'ok')
   req=send.call_args.args[0];headers={k.lower():v for k,v in req.header_items()}
   self.assertEqual(req.full_url,m['endpoint'])
   self.assertEqual(headers['authorization'],'Bearer synthetic-go')
   self.assertTrue(headers['user-agent'].startswith('opencode/'))
   self.assertEqual(headers['x-opencode-org-id'],'synthetic-org')
   self.assertEqual(headers['x-opencode-session'],headers['x-opencode-session-id'])
   self.assertEqual(headers['x-opencode-client'],'cli')
   self.assertTrue(headers['x-opencode-request'].startswith('msg_'))
 def test_forbidden_response_does_not_claim_key_is_invalid(self):
  router=BrainRouter(self.models,self.keys)
  error=urllib.error.HTTPError(self.models[0]['endpoint'],403,'Forbidden',{},io.BytesIO(b'Cloudflare blocked request'))
  with patch('vigil_brain.urllib.request.urlopen',side_effect=error):
   with self.assertRaises(Failure) as caught:router.http(self.models[0],{'text':'synthetic'},5)
   self.assertEqual(caught.exception.kind,'forbidden')
 def test_first_two_fail_third_answers(self):
  calls=[]
  def transport(m,prompt,timeout,probe=False):
   calls.append(m['provider']);self.assertLessEqual(timeout,20)
   if m['provider'] in ['opencode-go','openrouter']:raise Failure('429',time.time()+60)
   return 'Third provider answered'
  router=BrainRouter(self.models,self.keys,transport)
  for i,m in enumerate(self.models):router.health[router.id(m)].update(status='green',latency=i)
  reply=router.complete({'text':'synthetic'})
  self.assertEqual(reply['provider'],'nvidia');self.assertFalse(reply['local'])
  self.assertEqual(calls,['opencode-go','openrouter','nvidia'])
  self.assertEqual(sum(s['status']=='amber' for s in router.snapshot()),2)
 def test_screen_vision_gate_and_local_json(self):
  calls=[]
  def fail(m,*args):calls.append(m);raise Failure('unavailable',time.time()+60)
  text=candidate('nvidia','text',False)
  router=BrainRouter([text]+self.models,self.keys,fail)
  reply=router.complete({'text':'Task: Unknown\nApp: Unclear','image':'synthetic'})
  self.assertTrue(reply['local']);self.assertTrue(all(m['vision'] for m in calls))
  self.assertEqual(json.loads(reply['text'])['choice'],'uncertain')
 def test_cooldown_persisted_and_expires(self):
  calls=[]
  def transport(m,*args):calls.append(m);raise Failure('429',time.time()+60)
  with tempfile.TemporaryDirectory() as folder:
   path=Path(folder)/'health.json';router=BrainRouter(self.models[:1],self.keys,transport,path)
   router.probe_all();self.assertEqual(len(calls),1)
   again=BrainRouter(self.models[:1],self.keys,transport,path)
   again.probe_all();self.assertEqual(len(calls),1)
   again.probe_all(time.time()+61);self.assertEqual(len(calls),2)
 def test_forbidden_models(self):
  for name in ['openai/test','gpt-6','vendor/GPT-something','codex-model']:
   self.assertFalse(BrainRouter.permitted(candidate('openrouter',name)))
 def test_visual_question_accepts_sentence_and_fails_over(self):
  calls=[]
  def transport(m,prompt,timeout,probe=False):
   calls.append(m['provider'])
   if m['provider']!='nvidia':raise Failure('429',time.time()+60)
   return 'A blue shirt.'
  router=BrainRouter(self.models,self.keys,transport)
  for i,m in enumerate(self.models):router.health[router.id(m)].update(status='green',latency=i)
  reply=router.complete({'purpose':'question','text':'What is this?','image':'synthetic'})
  self.assertEqual(reply['text'],'A blue shirt.');self.assertFalse(reply['local'])
  self.assertEqual(calls,['openrouter','nvidia'])
 def test_question_skips_paid_openrouter_and_never_invents_local_vision(self):
  calls=[]
  paid=candidate('openrouter','vendor/paid')
  router=BrainRouter([paid],self.keys,lambda *args:calls.append(args))
  reply=router.complete({'purpose':'question','text':'What is this?','image':'synthetic'})
  self.assertTrue(reply['local']);self.assertEqual(calls,[])
  self.assertEqual(reply['text'],"I couldn't get a clear answer just now.")
 def test_focus_still_rejects_non_classification_vision_answer(self):
  router=BrainRouter(self.models,self.keys,lambda *args:'A blue shirt.')
  reply=router.complete({'text':'Task: synthetic','image':'synthetic'})
  self.assertTrue(reply['local']);self.assertEqual(json.loads(reply['text'])['choice'],'uncertain')
 def test_single_use_activation_and_token_hash_only(self):
  with tempfile.TemporaryDirectory() as folder:
   path=Path(folder)/'devices.json';registry=DeviceRegistry(path)
   registry.state['codes'][digest('synthetic-code')]={'edition':'macy','expires':time.time()+60}
   self.assertIsNone(registry.activate('synthetic-code','keith','device'))
   token=registry.activate('synthetic-code','macy','device');self.assertIsNotNone(token)
   self.assertEqual(registry.valid(token)['edition'],'macy')
   self.assertIsNone(registry.activate('synthetic-code','macy','device'))
   self.assertNotIn(token,path.read_text())
 def test_unsigned_enrolment_rejected(self):
  with tempfile.TemporaryDirectory() as folder:
   registry=DeviceRegistry(Path(folder)/'devices.json')
   with self.assertRaises(Exception):enrol_device(registry,{'bundle':'com.evil.app','device':'synthetic-device-value','transaction':'unsigned'})

if __name__=='__main__':unittest.main()
