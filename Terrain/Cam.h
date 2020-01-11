#pragma once

// Objective-C++ ports of original https://github.com/sasmaster/TrackballControls by sasmaster

#import <simd/simd.h>

#define FloatInfinity std::numeric_limits<float>::infinity()
#define SQRT1_2  0.7071067811865476

class Cam {
  
    private:
        
        enum TCB_STATE {
            NONE = 0,
            ROTATE,
            ZOOM,
            PAN
        };
        
        enum MOUSE_BUTTONS {
            LEFT   = 1<<0,
            MIDDLE = 1<<2,
            RIGHT  = 1<<1
        };
        
        double fov = 60.0;
        double near = 0.0001;
        double far = 10000.0;
        
        double minDistance = 0.5;
        double maxDistance = 3.5;//FloatInfinity;
        
        simd::float4 screen = simd::float4{0,0,1920,1080};
        double aspect = screen.z/screen.w;

    
        simd::float3 camEye;
        simd::float3 camUp = simd::float3{0.0,1.0,0.0};
        
           
        simd::float3 target = simd::float3{0,0,0};
        simd::float3 lastPos = simd::float3{0,0,0};
        simd::float3 eye = simd::float3{0,0,0};
     
        simd::float3 rotStart = simd::float3{0,0,0};
        simd::float3 rotEnd = simd::float3{0,0,0};
    
        simd::float2 zoomStart = simd::float2{0,0};
        simd::float2 zoomEnd = simd::float2{0,0};
        
        simd::float2 panStart = simd::float2{0,0};
        simd::float2 panEnd = simd::float2{0,0};
        
        TCB_STATE state = TCB_STATE::NONE;
        
        double rotateSpeed = 1.0f;
        double zoomSpeed = 0.3f;
        double panSpeed = 0.3f;
    
        double dynamicDampingFactor = 0.2f;
    
        bool enabled = true;
    
        bool noRotate = false;
        bool noZoom = false;
        bool noPan = false;
    
        bool noRoll = false;
    
        bool staticMoving = false;
        
        double radians(float degrees) {
            return ((1.0f/180.0f)*float(M_PI))*degrees;
        }
        
        simd::float4x4 _perspective(float fovy, float aspect, float near,float far) {
            
            float angle  = radians(fovy)*0.5;
            float yScale = 1.0f/tan(angle);
            float xScale = yScale/aspect;
            float zScale = far/(far-near);
            
            simd::float4 P = 0.0f;
            simd::float4 Q = 0.0f;
            simd::float4 R = 0.0f;
            simd::float4 S = 0.0f;
            
            P.x =  xScale;
            Q.y =  yScale;
            R.z =  zScale;
            R.w =  1.0f;
            S.z = -near*zScale;
                        
            return simd::float4x4(P,Q,R,S);
        }

        simd::float4x4 _lookAt(simd::float3 eye, simd::float3 center, simd::float3 up) {
        
            simd::float3 zAxis = simd::normalize(center-eye);
            simd::float3 xAxis = simd::normalize(simd::cross(up,zAxis));
            simd::float3 yAxis = simd::cross(zAxis,xAxis);
            
            simd::float4 P;
            simd::float4 Q;
            simd::float4 R;
            simd::float4 S;
            
            P.x = xAxis.x;
            P.y = yAxis.x;
            P.z = zAxis.x;
            P.w = 0.0f;
            
            Q.x = xAxis.y;
            Q.y = yAxis.y;
            Q.z = zAxis.y;
            Q.w = 0.0f;
            
            R.x = xAxis.z;
            R.y = yAxis.z;
            R.z = zAxis.z;
            R.w = 0.0f;
            
            S.x = -simd::dot(xAxis,eye);
            S.y = -simd::dot(yAxis,eye);
            S.z = -simd::dot(zAxis,eye);
            S.w =  1.0f;
            
            return simd::float4x4(P,Q,R,S);
        }
    
        void calc() {
            
            this->projectionMatrix = _perspective(this->fov,this->aspect,this->near,this->far);
            this->viewMatrix = _lookAt(this->camEye,this->target,this->camUp);
            
            this->matrix = this->projectionMatrix*this->viewMatrix;
        }
                
        simd::float3 GetMouseProjectionOnBall(int clientX, int clientY) {
            
            simd::float3 mouseOnBall = simd::float3{
                (clientX-this->screen.z*0.5f)/(screen.z*0.5f),
                (this->screen.w*0.5f-clientY)/(screen.w*0.5f),
                0.0f
            };

            double length = simd::length(mouseOnBall);

            if(noRoll) {
                if(length<SQRT1_2) {
                    mouseOnBall.z = sqrt(1.0-length*length);
                }
                else {
                    mouseOnBall.z = (0.5/length);
                }
            }
            else if(length>1.0) {
                mouseOnBall = simd::normalize(mouseOnBall);
            }
            else {
                mouseOnBall.z = sqrt(1.0-length*length);
            }

            this->eye = this->target-this->camEye;
                
            simd::float3 projection = simd::normalize(this->camUp)*mouseOnBall.y;
            
            projection+=simd::normalize(simd::cross(this->camUp,this->eye))*mouseOnBall.x;
            projection+=simd::normalize(this->eye)*mouseOnBall.z;
                    
            return projection;
        }
        
        simd::float2 GetMouseOnScreen(int clientX, int clientY)  {
            return simd::float2{
                (float)(clientX-this->screen.x)/this->screen.z,
                (float)(clientY-this->screen.y)/this->screen.w
            };
        }
        
        void RotateCamera() {
                        
            double len = simd::length(this->rotStart)*simd::length(this->rotEnd);
            if(len<=DBL_EPSILON) return;

            double angle = acos(simd::dot(this->rotStart,this->rotEnd)/len);
            if(isnan(angle)||angle<=DBL_EPSILON) return;
            angle*=this->rotateSpeed;

            simd::float3 cross = simd::cross(this->rotStart,this->rotEnd);
            if(simd::length_squared(cross)<=DBL_EPSILON) return;
            simd::float3 axis = simd::normalize(cross);
            simd::quatf quaternion = simd_quaternion(-angle,axis);
            this->eye = simd_act(quaternion,this->eye);
            this->camUp = simd_act(quaternion,this->camUp);
            this->rotEnd = simd_act(quaternion,this->rotEnd);

            if(this->staticMoving) {
                this->rotStart = this->rotEnd;
            }
            else {
                quaternion = simd_quaternion(angle*(this->dynamicDampingFactor-1.0f),axis);
                this->rotStart = simd_act(quaternion,this->rotStart);
            }
        }
        
        void ZoomCamera() {
            
            double factor = 1.0f+(this->zoomEnd.y-this->zoomStart.y)*this->zoomSpeed;
            if(factor!=1.0f&&factor>0.0f) {
                this->eye*=factor;
            }
            
            if(this->staticMoving) {
                this->zoomStart = this->zoomEnd;
            }
            else {
                this->zoomStart.y+=(this->zoomEnd.y-this->zoomStart.y)*this->dynamicDampingFactor;
            }
        }
        
        void PanCamera() {

            simd::float2 mouseChange = this->panEnd-this->panStart;

            if(simd::length(mouseChange)!=0.0f) {
                
                mouseChange*=simd::length(this->eye)*this->panSpeed;
                simd::float3 pan = simd::normalize(simd::cross(this->eye,this->camUp))*-mouseChange.x;
                pan+=simd::normalize(this->camUp)*-mouseChange.y;
                
                this->camEye+=pan;
                this->target+=pan;
                
                if(this->staticMoving) {
                    this->panStart = this->panEnd;
                }
                else {
                    this->panStart+=(this->panEnd-this->panStart)*this->dynamicDampingFactor;
                }
            }
        }
                
        void CheckDistances() {
            if(!this->noZoom||!this->noPan) {
                if(simd::length_squared(this->camEye)>this->maxDistance*this->maxDistance) {
                    this->camEye = simd::normalize(this->camEye)*this->maxDistance;
                }
                if(simd::length_squared(this->eye)<this->minDistance*this->minDistance) {
                    this->eye = simd::normalize(this->eye)*this->minDistance;
                    this->camEye = this->target + this->eye;
                }
            }
        }
        
    public:
        
        simd::float4x4 matrix;
        
        simd::float4x4 projectionMatrix;
        simd::float4x4 viewMatrix;
                
        Cam(const simd::float3 pos,simd::float3 target = simd::float3{0,0,0}) {
            this->camEye = pos;
            this->target = target;            
            this->calc();
        }
        
        void setFov(double fov) { this->fov = fov; }
        
        void setNear(double near) { this->near = near; }
        void setFar(double far) { this->far = far; }
        
        void setMinDistance(double minDistance) { this->minDistance = minDistance; }
        void setMaxDistance(double maxDistance) { this->maxDistance = maxDistance; }
        
        void setScreen(float x,float y,float w,float h) {
            this->screen = simd::float4{x,y,w,h};
            this->aspect = screen.z/screen.w;
        }
        
        void setRotate(bool active) { this->noRotate = !active; }
        void setZoom(bool active) { this->noZoom = !active; }
        void setPan(bool active) { this->noPan = !active; }
        void setRoll(bool active) { this->noRoll = !active; }
        
        
        void update() {

            this->eye = this->camEye-this->target;
             
            if(!this->noRotate) this->RotateCamera();
            if(!this->noZoom) this->ZoomCamera();
            if(!this->noPan) this->PanCamera();
            
            this->camEye = this->target+this->eye;
            CheckDistances();
            
            if(simd::length_squared(this->target-this->eye)<=DBL_EPSILON) return;
            this->calc();

            if(simd::length_squared(this->lastPos-this->camEye)>0.0f) this->lastPos = this->camEye;
        }
        
        void mouseDown(unsigned int mouseButtons,int xpos,int ypos) {
            if(this->state==TCB_STATE::NONE) {
                if(mouseButtons==MOUSE_BUTTONS::LEFT) {
                    this->state = TCB_STATE::ROTATE;
                    if(!this->noRotate) {
                        this->rotStart = GetMouseProjectionOnBall(xpos,ypos);
                        this->rotEnd = this->rotStart;
                    }
                }
                else if(mouseButtons==MOUSE_BUTTONS::RIGHT) {
                    this->state = TCB_STATE::PAN;
                    if(!this->noPan) {
                        this->panStart = GetMouseOnScreen(screen.z-xpos,ypos);
                        this->panEnd = this->panStart;
                    }
                }
            }
        }
        
        void mouseUp() {
            if(!this->enabled) return;
            this->state = TCB_STATE::NONE;
        }
        
        void mouseMove(int xpos,int ypos) {
            if(!this->enabled) return;
            if(this->state==TCB_STATE::ROTATE&&!this->noRotate) {
                this->rotEnd = GetMouseProjectionOnBall(screen.z-xpos,ypos);
            }
            else if(this->state==TCB_STATE::PAN&&!this->noPan) {
                this->panEnd = GetMouseOnScreen(xpos,ypos);
            }
        }
        
        void mouseWheel(double deltaX, double deltaY) {
            if(!this->enabled) return;
            this->zoomStart.y+=(deltaY!=0.0)?(deltaY/3.0f)*0.05f:0.0f;
        }
             
        ~Cam() {
            
        }
};

