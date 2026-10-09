// Touchline Live: read-only discovery session. No save-file support or target writes.
#include <mach/mach.h>
#include <mach/mach_vm.h>
#include <libproc.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cstdint>
#include <cstring>
#include <cerrno>
#include <fstream>
#include <sstream>
#include <iostream>
#include <vector>
#include <unordered_set>
#include <chrono>
#include <thread>
#include <algorithm>
extern "C" int task_read_for_pid(mach_port_name_t, int, mach_port_name_t*);
using U = uint64_t;
static mach_port_t port=0;
static U bytesRead=0, readCalls=0;
static double now(){return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch()).count();}
template<class T> T word(const unsigned char* p){T x;memcpy(&x,p,sizeof x);return x;}
static bool readmem(U a,void* b,size_t n){if(!a||!n||n>4*1024*1024||a>UINT64_MAX-n)return false;mach_vm_size_t got=0;readCalls++;auto k=mach_vm_read_overwrite(port,a,n,(mach_vm_address_t)b,&got);bytesRead+=got;return k==0&&got==n;}
struct Region{U a,n;int prot;unsigned tag;};
static std::vector<Region> regions(){std::vector<Region> v;mach_vm_address_t a=0;natural_t d=0;for(int guard=0;guard<100000;guard++){mach_vm_size_t n=0;vm_region_submap_info_data_64_t i={};mach_msg_type_number_t c=VM_REGION_SUBMAP_INFO_COUNT_64;auto k=mach_vm_region_recurse(port,&a,&n,&d,(vm_region_recurse_info_t)&i,&c);if(k)break;if(i.is_submap){d++;continue;}if(!n||a>UINT64_MAX-n)break;v.push_back({a,n,i.protection,i.user_tag});a+=n;}return v;}
static bool heap(const Region&r){return (r.prot&3)==3&&!(r.prot&4)&&(r.tag==1||r.tag==2||r.tag==3||r.tag==4||r.tag==7||r.tag==8||r.tag==9||r.tag==11||r.tag==12);}
static void hexbytes(std::ostream&o,const unsigned char*b,size_t n){static char h[]="0123456789abcdef";for(size_t j=0;j<n;j++)o<<h[b[j]>>4]<<h[b[j]&15];}
int main(int argc,char**argv){
 if(argc!=3)return 64;int pid=atoi(argv[1]);std::string dir=argv[2];char path[PROC_PIDPATHINFO_MAXSIZE]={};
 if(!proc_pidpath(pid,path,sizeof path))return 65;std::string p=path,suffix="/Football Manager 2024/fm.app/Contents/MacOS/fm";
 if(p.size()<suffix.size()||p.substr(p.size()-suffix.size())!=suffix)return 65;
 struct stat st;if(lstat(dir.c_str(),&st)||!S_ISDIR(st.st_mode)||st.st_uid==0)return 65;
 if(task_read_for_pid(mach_task_self(),pid,&port)||!port){std::cerr<<"Read-only attachment denied: "<<strerror(errno)<<"\n";return 2;}
 // Discard administrator identity after acquiring the read-only task port.
 if(geteuid()==0&&(setgid(st.st_gid)||setuid(st.st_uid)))return 66;
 std::ofstream(dir+"/ready.txt")<<"pid "<<pid<<" uid "<<getuid()<<" read_only true\n";
 std::string last;bool anchorUsed=false;double expires=now()+3600;
 while(now()<expires){std::ifstream f(dir+"/request.txt");std::string line;getline(f,line);std::istringstream in(line);std::string id,op;in>>id>>op;if(id.empty()||id==last||id.find_first_not_of("0123456789")!=std::string::npos){std::this_thread::sleep_for(std::chrono::milliseconds(50));continue;}last=id;
  std::ofstream out(dir+"/response.tmp");auto start=now();U b0=bytesRead,c0=readCalls;out<<"REQUEST "<<id<<" "<<op<<"\n";
  if(op=="quit"){out<<"BYE\n";expires=0;}
  else if(op=="map"){for(auto&r:regions())out<<"REGION "<<std::hex<<r.a<<" "<<r.n<<std::dec<<" "<<r.prot<<" "<<r.tag<<"\n";}
  else if(op=="read"||op=="batch"){U a,n;size_t total=0;while(in>>std::hex>>a>>n){if(n>4*1024*1024||total+n>64*1024*1024){out<<"ERROR read budget\n";break;}total+=n;std::vector<unsigned char>b(n);out<<"READ "<<std::hex<<a<<" "<<n<<" ";if(readmem(a,b.data(),n))hexbytes(out,b.data(),n);else out<<"FAILED";out<<"\n";}}
  else if(op=="anchors"||op=="refs"){
   if(op=="anchors"&&anchorUsed){out<<"ERROR anchor pass already used\n";}else{
    bool anchors=op=="anchors";anchorUsed|=anchors;std::unordered_set<U> targets;U x;while(in>>std::hex>>x)targets.insert(x);
    if(targets.size()>4096){out<<"ERROR too many targets\n";}else{
     size_t hits=0;U scanned=0;bool limited=false;std::vector<unsigned char>b(4*1024*1024);
     for(auto&r:regions()){if(!(heap(r)||(!anchors&&(r.prot&3)==3&&r.tag==0)))continue;
      for(U off=0;off<r.n;off+=b.size()){
       if(scanned>=8ULL*1024*1024*1024||now()-start>45||hits>=20000){limited=true;break;}
       size_t n=std::min<U>(b.size(),r.n-off);scanned+=n;if(!readmem(r.a+off,b.data(),n))continue;
       for(size_t j=0;j+(anchors?8:8)<=n;j+=anchors?4:8){U value=anchors?word<uint32_t>(&b[j]):word<U>(&b[j]);if(!targets.count(value))continue;
        if(anchors){unsigned char ctx[0x410];U u=r.a+off+j;if(u<0x400||!readmem(u-0x400,ctx,sizeof ctx))continue;auto q=ctx+0x400;auto ca=word<uint16_t>(q-0x1bc),pa=word<uint16_t>(q-0x1ba),year=word<uint16_t>(q-0x136);if(word<uint32_t>(q+4)!=value||!ca||ca>200||!pa||pa>200||year<1850||year>2100)continue;out<<"ANCHOR "<<std::hex<<u<<" "<<value<<" ";hexbytes(out,ctx,sizeof ctx);out<<"\n";}
        else out<<"HIT "<<std::hex<<(r.a+off+j)<<" "<<value<<"\n";hits++;
       }
      }if(limited)break;
     }out<<"SCAN "<<std::dec<<scanned<<" "<<hits<<" limited "<<limited<<"\n";
    }
   }
  }else out<<"ERROR unknown operation\n";
  out<<"METRICS "<<std::dec<<bytesRead-b0<<" "<<readCalls-c0<<" "<<now()-start<<"\n";out.close();rename((dir+"/response.tmp").c_str(),(dir+"/response-"+id+".txt").c_str());
 }
 mach_port_deallocate(mach_task_self(),port);return 0;
}
