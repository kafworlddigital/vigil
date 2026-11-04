"""Vigil-only, stateless inference. No shared-brain imports, histories, prompt logs or screen files."""
from pathlib import Path
import base64,concurrent.futures,datetime,email.utils,hashlib,hmac,http.server,json,os,secrets,ssl,threading,time,urllib.request,urllib.error

ROOT=Path(__file__).resolve().parent
PRIVATE=Path(os.environ.get('VIGIL_PRIVATE','/srv/projects/vigil-private'))
def stamp(value=None):return datetime.datetime.fromtimestamp(value or time.time(),datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
def atomic(path,value):
    temp=path.with_suffix('.tmp');temp.write_text(json.dumps(value,indent=2));temp.chmod(0o600);temp.replace(path)
def digest(value):return hashlib.sha256(value.encode()).hexdigest()

class BrainRouter:
    def __init__(self,models,keys,transport=None,state_path=None):
        self.models=[m for m in models if self.permitted(m)];self.keys=keys;self.transport=transport or self.http
        self.lock=threading.RLock();self.state_path=state_path;self.health={};self.probing=False
        self.session='vigil-brain-'+secrets.token_hex(16)
        if state_path and state_path.exists():
            try:self.health=json.loads(state_path.read_text())
            except (ValueError,OSError):pass
        for model in self.models:self.health.setdefault(self.id(model),self.initial(model))
    @staticmethod
    def permitted(m):
        if any(x in m['model'].lower() for x in ['openai','gpt','codex']):return False
        domains={'opencode-go':'opencode.ai','opencode':'opencode.ai','openrouter':'openrouter.ai','nvidia':'integrate.api.nvidia.com','ollama-cloud':'ollama.com'}
        u=urllib.parse.urlparse(m['endpoint'])
        return u.scheme=='https' and u.hostname==domains.get(m['provider']) and not m['model'].startswith('openrouter/')
    @staticmethod
    def id(m):return m['provider']+':'+m['model']
    @staticmethod
    def initial(m):return dict(id=BrainRouter.id(m),provider=m['provider'],model=m['model'],vision=m['vision'],status='amber')
    def persist(self):
        if self.state_path:atomic(self.state_path,self.health)
    def snapshot(self):
        with self.lock:
            return sorted([dict(self.health[self.id(m)]) for m in self.models],key=lambda x:({'green':0,'amber':1,'red':2}.get(x['status'],2),x.get('latency',20),x['id']))
    @staticmethod
    def reset(state):
        try:return datetime.datetime.fromisoformat(state.get('cooldownUntil','').replace('Z','+00:00')).timestamp()
        except ValueError:return 0
    def http(self,m,prompt,timeout,probe=False):
        messages=[]
        if prompt.get('system'):messages.append({'role':'system','content':str(prompt['system'])[:2000]})
        user={'role':'user','content':str(prompt.get('text',''))[:14000]}
        if prompt.get('image'):
            if m['protocol']=='ollama':user['images']=[prompt['image']]
            else:user['content']=[{'type':'text','text':user['content']},{'type':'image_url','image_url':{'url':'data:'+prompt.get('mime','image/jpeg')+';base64,'+prompt['image']}}]
        messages.append(user)
        body={'model':m['model'],'messages':messages,'stream':False,'max_tokens':256 if probe else 512}
        if m['protocol']=='ollama':
            body.pop('max_tokens');body['think']=False;body['options']={'num_predict':256 if probe else 512}
        if m['provider']=='openrouter':body['provider']={'max_price':dict(prompt=0,completion=0,request=0,image=0)};body['reasoning']={'enabled':False}
        headers={'Authorization':'Bearer '+self.keys.get(m['provider'],''),'Content-Type':'application/json','User-Agent':'Vigil/1.0','x-opencode-session':self.session}
        req=urllib.request.Request(m['endpoint'],data=json.dumps(body).encode(),headers=headers)
        try:
            with urllib.request.urlopen(req,timeout=timeout) as response:
                d=json.load(response)
            message=d.get('message',{}) if m['protocol']=='ollama' else d.get('choices',[{}])[0].get('message',{})
            text=message.get('content','').strip()
            if not text:raise Failure('empty',time.time()+60)
            return text
        except urllib.error.HTTPError as e:
            raw=e.read(8000).decode(errors='replace').lower()
            if e.code==429 or any(x in raw for x in ['limit reached','quota','rate limit','usage limit']):
                retry=e.headers.get('Retry-After','')
                try:reset=time.time()+max(1,float(retry))
                except ValueError:
                    try:reset=email.utils.parsedate_to_datetime(retry).timestamp()
                    except (ValueError,TypeError):reset=time.time()+1800
                raise Failure('429' if e.code==429 else 'limit',reset) from None
            raise Failure('auth' if e.code in [401,403] else 'http '+str(e.code),time.time()+(1800 if e.code in [401,402,403,404] else 60)) from None
        except (TimeoutError,urllib.error.URLError):raise Failure('timeout',time.time()+60) from None
    def record(self,m,started,error=None):
        state=self.initial(m);state.update(checkedAt=stamp(),latency=round(time.monotonic()-started,3),status='green')
        if error:
            kind=error.kind if isinstance(error,Failure) else 'invalid reply'
            state.update(status='amber' if kind in ['limit','429'] else 'red',error=kind,cooldownUntil=stamp(error.reset if isinstance(error,Failure) else time.time()+60))
        with self.lock:self.health[self.id(m)]=state
    def probe_all(self,now=None):
        now=now or time.time()
        with self.lock:
            if self.probing:return
            self.probing=True
            pending=[m for m in self.models if self.reset(self.health[self.id(m)])<=now]
        def probe(m):
            started=time.monotonic()
            if not self.keys.get(m['provider']):self.record(m,started,Failure('auth',now+1800));return
            prompt={'text':'Reply ready.'}
            if m['vision']:
                prompt['image']=base64.b64encode((ROOT/'probe.png').read_bytes()).decode();prompt['mime']='image/png';prompt['text']='Reply ready if you can see this plain image.'
            try:self.transport(m,prompt,20,True);self.record(m,started)
            except Exception as e:self.record(m,started,e)
        try:
            if pending:
                with concurrent.futures.ThreadPoolExecutor(max_workers=len(pending)) as pool:list(pool.map(probe,pending))
        finally:
            with self.lock:self.probing=False;self.persist()
    @staticmethod
    def local(prompt):
        if prompt.get('image'):
            lines=prompt.get('text','').lower().splitlines();words={s.strip('.,:;!?') for s in (lines[0] if lines else '').split() if len(s)>4}
            matching=sum(word in '\n'.join(lines[1:]) for word in words)
            decision=dict(choice='on_task',p_on=.6,p_off=0,p_uncertain=.4) if matching>=2 else dict(choice='uncertain',p_on=0,p_off=0,p_uncertain=1)
            return dict(text=json.dumps(decision),provider='on-device',model='Local screen heuristic',local=True)
        return dict(text='One small step towards your task. Your timer and parking lot are ready when you are.',provider='on-device',model='Local reply',local=True)
    def complete(self,prompt,blocked=frozenset(),budget=160):
        deadline=time.monotonic()+budget
        with self.lock:byid={self.id(m):m for m in self.models};ranked=self.snapshot()
        for state in ranked:
            m=byid[state['id']]
            if m['provider'] in blocked or not self.keys.get(m['provider']) or self.reset(state)>time.time() or (prompt.get('image') and not m['vision']):continue
            if deadline-time.monotonic()<1:break
            started=time.monotonic()
            try:
                timeout=min(20,max(1,deadline-time.monotonic()))
                text=self.transport(m,prompt,timeout)
                if prompt.get('image'):
                    text=text.strip();text=text.removeprefix('```json').removeprefix('```').removesuffix('```').strip();decision=json.loads(text)
                    nums=[decision.get(k) for k in ['p_on','p_off','p_uncertain']]
                    if decision.get('choice') not in ['on_task','off_task','uncertain'] or not all(isinstance(x,(int,float)) and 0<=x<=1 for x in nums) or abs(sum(nums)-1)>.02:raise Failure('invalid reply',time.time()+60)
                self.record(m,started)
                with self.lock:self.persist()
                return dict(text=text,provider=m['provider'],model=m['model'],local=False)
            except Exception as e:self.record(m,started,e)
        with self.lock:self.persist()
        return self.local(prompt)
class Failure(Exception):
    def __init__(self,kind,reset):self.kind=kind;self.reset=reset

class DeviceRegistry:
    def __init__(self,path):self.path=path;self.lock=threading.Lock();self.state=json.loads(path.read_text()) if path.exists() else {'tokens':{},'codes':{}}
    def activate(self,code,edition,device):
        with self.lock:
            record=self.state['codes'].get(digest(code))
            if not record or record['expires']<time.time() or record['edition']!=edition:return None
            del self.state['codes'][digest(code)];token=secrets.token_urlsafe(40)
            self.state['tokens'][digest(token)]={'edition':edition,'device':digest(device),'created':stamp()}
            atomic(self.path,self.state);return token
    def valid(self,token):
        with self.lock:return self.state['tokens'].get(digest(token))

def serve():
    private=PRIVATE;private.mkdir(mode=0o700,exist_ok=True)
    keys=json.loads((private/'job3-keys.json').read_text())
    registry=DeviceRegistry(private/'devices.json')
    router=BrainRouter(json.loads((ROOT/'models.json').read_text()),keys,state_path=private/'brain-health.json')
    def monitor():
        while True:
            router.probe_all();time.sleep(1800)
    threading.Thread(target=monitor,daemon=True).start()
    limits={};lock=threading.Lock();gate=threading.BoundedSemaphore(8)
    class Handler(http.server.BaseHTTPRequestHandler):
        server_version='Vigil'
        def log_message(self,*args):pass
        def reply(self,status,value):
            data=json.dumps(value).encode();self.send_response(status);self.send_header('Content-Type','application/json');self.send_header('Cache-Control','no-store');self.send_header('Content-Length',str(len(data)));self.end_headers();self.wfile.write(data)
        def do_GET(self):
            if self.path.endswith('/ready'):self.reply(200,{'service':'Vigil','ready':True});return
            if not registry.valid(self.headers.get('Authorization','').removeprefix('Bearer ')):self.reply(401,{'error':'auth'});return
            if self.path.endswith('/health'):self.reply(200,router.snapshot())
            else:self.reply(404,{'error':'unknown route'})
        def do_POST(self):
            try:length=int(self.headers.get('Content-Length','0'))
            except ValueError:self.reply(400,{'error':'invalid request'});return
            if not 0<length<=4_000_000:self.reply(413,{'error':'request too large'});return
            # Rate-limit authentication attempts as well as inference; never log the supplied token or body.
            identity=digest(self.headers.get('Authorization','')) if not self.path.endswith(('/activate','/enrol')) else self.client_address[0]
            now=time.time()
            with lock:
                recent=[t for t in limits.get(identity,[]) if now-t<3600]
                if len(recent)>=120:self.reply(429,{'error':'limit'});return
                limits[identity]=recent+[now]
                if len(limits)>1000:
                    for k in list(limits):
                        if not limits[k] or now-limits[k][-1]>3600:limits.pop(k,None)
            try:data=json.loads(self.rfile.read(length))
            except (ValueError,UnicodeError):self.reply(400,{'error':'invalid JSON'});return
            if self.path.endswith('/enrol'):
                try: token=enrol_device(registry,data)
                except Exception: self.reply(401,{'error':'unverified install'});return
                self.reply(200,{'token':token});return
            if self.path.endswith('/activate'):
                token=registry.activate(str(data.get('code','')),str(data.get('edition','')),str(data.get('device','')))
                self.reply(200,{'token':token}) if token else self.reply(401,{'error':'invalid or expired activation code'});return
            if not registry.valid(self.headers.get('Authorization','').removeprefix('Bearer ')):self.reply(401,{'error':'auth'});return
            if self.path.endswith('/test'):
                router.probe_all()
                deadline=time.monotonic()+22
                while router.probing and time.monotonic()<deadline:time.sleep(.1)
                self.reply(200,router.snapshot());return
            if not self.path.endswith('/answer'):self.reply(404,{'error':'unknown route'});return
            if not isinstance(data,dict) or not isinstance(data.get('text'),str) or len(data['text'])>14000:self.reply(400,{'error':'invalid prompt'});return
            if data.get('mime','image/jpeg') not in ['image/jpeg','image/png']:self.reply(400,{'error':'invalid image'});return
            if not gate.acquire(blocking=False):self.reply(503,{'error':'busy, use app fallback'});return
            try:self.reply(200,router.complete(data))
            finally:gate.release()
    server=http.server.ThreadingHTTPServer(('127.0.0.1',8798),Handler);server.daemon_threads=True;server.serve_forever()
def enrol_device(registry,data):
    from appstoreserverlibrary.signed_data_verifier import SignedDataVerifier
    from appstoreserverlibrary.models.Environment import Environment
    bundle=str(data.get('bundle',''));device=str(data.get('device',''));transaction=str(data.get('transaction',''))
    apps=json.loads((PRIVATE/'apple-apps.json').read_text())
    if bundle not in apps or not 20<=len(device)<=100 or len(transaction)>50000:raise ValueError('invalid install')
    roots=[p.read_bytes() for p in (ROOT/'apple-roots').glob('*.cer')]
    payload=None
    for environment in [Environment.SANDBOX,Environment.PRODUCTION]:
        try:
            payload=SignedDataVerifier(roots,True,environment,bundle,int(apps[bundle])).verify_and_decode_app_transaction(transaction)
            break
        except Exception:pass
    if payload is None:raise ValueError('unverified install')
    # Bind one enrolment to the Apple-signed device verification value and local installation.
    # Keep hashes only: neither the transaction nor Apple account data is persisted.
    claim=digest(str(payload.deviceVerification)+bundle)
    with registry.lock:
        claims=registry.state.setdefault('claims',{})
        if claim in claims and claims[claim]!=digest(device):raise ValueError('already enrolled')
        if sum(v==digest(device) for v in claims.values())>4:raise ValueError('device bound')
        claims[claim]=digest(device)
        token=secrets.token_urlsafe(40)
        registry.state['tokens'][digest(token)]={'edition':'macy' if '.vigil.m.' in bundle else 'keith','device':digest(device),'created':stamp()}
        atomic(registry.path,registry.state)
        return token

if __name__=='__main__':serve()
