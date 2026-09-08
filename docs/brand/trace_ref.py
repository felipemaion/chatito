import cv2, numpy as np, subprocess, re, os, sys
from PIL import Image
S=os.path.dirname(os.path.abspath(__file__))
im=np.array(Image.open('/Users/maion/.claude/image-cache/b7b96c85-bb94-47b3-b6d0-2bd63509845a/6.png').convert('RGB'))
H,W=im.shape[:2]; print('size',W,H,file=sys.stderr)
hsv=cv2.cvtColor(im,cv2.COLOR_RGB2HSV)
dark=((hsv[:,:,2]<150)|((hsv[:,:,1]>120)&(hsv[:,:,2]<200))).astype(np.uint8)*255
n,lab,st,cen=cv2.connectedComponentsWithStats(dark)
bird=np.zeros_like(dark); bub=np.zeros_like(dark)
for i in range(1,n):
    x,y,w,h,a=st[i]
    if a<30: continue
    (bub if x>740 else bird)[lab==i]=255
    print(i,(x,y,w,h,a),'bubble' if x>740 else 'bird',file=sys.stderr)
# cor média do verde
px=im[bird>0]; print('green', '#%02X%02X%02X'%tuple(np.median(px,axis=0).astype(int)), file=sys.stderr)
# buracos (regiões brancas fechadas) do pássaro
inv=cv2.bitwise_not(bird)
n2,lab2,st2,cen2=cv2.connectedComponentsWithStats(inv)
for i in range(1,n2):
    x,y,w,h,a=st2[i]
    if a<20 or x==0 or y==0 or x+w>=W or y+h>=H: continue
    circ=a/(np.pi*(max(w,h)/2)**2)
    print('hole',i,(x,y,w,h,a),'circ %.2f'%circ,'cen',cen2[i].round(1),file=sys.stderr)
Image.fromarray(bird).save(S+'/bird_mask.png')

# ---- vetorizar o pássaro (todos os componentes) ----
p=S+'/bird.pbm'; Image.fromarray(255-bird).convert('1').save(p)
svg=subprocess.run(['potrace','-s','-t','20','-a','1.3','-O','0.6','-o','-',p],capture_output=True,text=True).stdout
tr=re.search(r'<g transform="([^"]+)"',svg).group(1); paths=re.findall(r'<path d="([^"]+)"',svg)
G='#106B1F'
out=['<svg xmlns="http://www.w3.org/2000/svg" viewBox="20 30 1010 650">',
     '  <!-- Piriquito: silhueta chapada com penas em negativo, olho e balão vetoriais -->',
     f'  <g transform="{tr}" fill="{G}">']+[f'    <path d="{d}"/>' for d in paths]+['  </g>',
     '  <!-- olho -->',
     '  <circle cx="617" cy="168" r="30" fill="#FFFFFF"/>',
     f'  <circle cx="621" cy="171" r="19" fill="{G}"/>',
     '  <circle cx="628" cy="162" r="6.5" fill="#FFFFFF"/>',
     '  <!-- balão -->',
     f'  <path d="M886 52 C960 52 1010 96 1010 152 C1010 206 960 250 886 250 C862 250 840 246 822 238 L772 262 L796 220 C774 202 762 178 762 152 C762 96 812 52 886 52 Z" fill="#FFFFFF" stroke="{G}" stroke-width="12" stroke-linejoin="round"/>',
     f'  <g fill="none" stroke="{G}" stroke-width="13" stroke-linecap="round">',
     '    <path d="M842 118 Q818 155 842 192"/><path d="M930 118 Q954 155 930 192"/>',
     '  </g>',
     f'  <g fill="{G}"><circle cx="862" cy="170" r="9"/><circle cx="886" cy="170" r="9"/><circle cx="910" cy="170" r="9"/></g>',
     '</svg>']
open(S+'/flat.svg','w').write('\n'.join(out)); print('svg ok',file=sys.stderr)
