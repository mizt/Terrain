#import <Cocoa/Cocoa.h>
#import <MetalKit/MetalKit.h>
#import <objc/runtime.h>

void addMethod(Class cls,NSString *method,id block,const char *type,bool isClassMethod=false) {
        
    SEL sel = NSSelectorFromString(method);
    int ret = ([cls respondsToSelector:sel])?1:(([[cls new] respondsToSelector:sel])?2:0);                
    if(ret) {
        class_addMethod(cls,(NSSelectorFromString([NSString stringWithFormat:@"_%@",(method)])),method_getImplementation(class_getInstanceMethod(cls,sel)),type);
        class_replaceMethod((ret==1)?object_getClass((id)cls):cls,sel,imp_implementationWithBlock(block),type);
    }
    else {
        class_addMethod((isClassMethod)?object_getClass((id)cls):cls,sel,imp_implementationWithBlock(block),type);
    }
}

// https://developer.apple.com/library/archive/samplecode/MetalBasicTessellation/Introduction/Intro.html
class TessellationPipeline {
    
    private:
        
        id<MTLDevice> _device;
        id<MTLCommandQueue> _commandQueue;
        id<MTLLibrary> _library;
        
        id<MTLComputePipelineState> _computePipelineQuad;
        id<MTLRenderPipelineState> _renderPipelineQuad;
        
        id<MTLBuffer> _tessellationFactorsBuffer;
        id<MTLBuffer> _controlPointsBufferTriangle;
        id<MTLBuffer> _controlPointsBufferQuad;
        
        id <MTKViewDelegate> delegate;
        
        bool _wireframe;
        
        bool didSetupMetal() {
          
            // Use the default device
            this->_device = MTLCreateSystemDefaultDevice();
            if(!this->_device) {
                NSLog(@"Metal is not supported on this device");
                return false;
            }
            
            if(![this->_device supportsFeatureSet:MTLFeatureSet_OSX_GPUFamily1_v1]) {
                NSLog(@"Tessellation is not supported on this device");
                return false;
            }
            
            // Create a new command queue
            this->_commandQueue = [this->_device newCommandQueue];
            
            // Load the default library
            NSError *error = nil;
            this->_library = [this->_device newLibraryWithFile:[NSString stringWithFormat:@"%@/%@",[[NSBundle mainBundle] bundlePath],@"TessellationFunctions.metallib"] error:&error];
            
            if(error!=nil) {
                return false;
            }
            
            return true;
        }


        bool didSetupComputePipelines() {
            
            NSError* computePipelineError;
            
            // Create compute pipeline for quad-based tessellation
            id <MTLFunction> kernelFunctionQuad = [this->_library newFunctionWithName:@"tessellation_kernel_quad"];
            this->_computePipelineQuad = [this->_device newComputePipelineStateWithFunction:kernelFunctionQuad error:&computePipelineError];
            if(!this->_computePipelineQuad) {
                NSLog(@"Failed to create compute pipeline (QUAD), error: %@", computePipelineError);
                return false;
            }
            
            return true;
        }

        bool didSetupRenderPipelinesWithMTKView(MTKView *view) {
            
            NSError *renderPipelineError = nil;
            
            // Create a reusable vertex descriptor for the control point data
            // This describes the inputs to the post-tessellation vertex function, declared with the 'stage_in' qualifier
            MTLVertexDescriptor* vertexDescriptor = [MTLVertexDescriptor vertexDescriptor];
            vertexDescriptor.attributes[0].format = MTLVertexFormatFloat4;
            vertexDescriptor.attributes[0].offset = 0;
            vertexDescriptor.attributes[0].bufferIndex = 0;
            vertexDescriptor.layouts[0].stepFunction = MTLVertexStepFunctionPerPatchControlPoint;
            vertexDescriptor.layouts[0].stepRate = 1;
            vertexDescriptor.layouts[0].stride = 4.0*sizeof(float);
            
            // Create a reusable render pipeline descriptor
            MTLRenderPipelineDescriptor *renderPipelineDescriptor = [MTLRenderPipelineDescriptor new];
            
            // Configure common render properties
            renderPipelineDescriptor.vertexDescriptor = vertexDescriptor;
            renderPipelineDescriptor.sampleCount = view.sampleCount;
            renderPipelineDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat;
            renderPipelineDescriptor.fragmentFunction = [_library newFunctionWithName:@"tessellation_fragment"];
            
            // Configure common tessellation properties
            renderPipelineDescriptor.tessellationFactorScaleEnabled = NO;
            renderPipelineDescriptor.tessellationFactorFormat = MTLTessellationFactorFormatHalf;
            renderPipelineDescriptor.tessellationControlPointIndexType = MTLTessellationControlPointIndexTypeNone;
            renderPipelineDescriptor.tessellationFactorStepFunction = MTLTessellationFactorStepFunctionConstant;
            renderPipelineDescriptor.tessellationOutputWindingOrder = MTLWindingClockwise;
            renderPipelineDescriptor.tessellationPartitionMode = MTLTessellationPartitionModeFractionalEven;

            // In OS X, the maximum tessellation factor is 64
            renderPipelineDescriptor.maxTessellationFactor = 64;
            
            // Create render pipeline for quad-based tessellation
            renderPipelineDescriptor.vertexFunction = [this->_library newFunctionWithName:@"tessellation_vertex_quad"];
            this->_renderPipelineQuad = [this->_device newRenderPipelineStateWithDescriptor:renderPipelineDescriptor error:&renderPipelineError];
            if (!_renderPipelineQuad) {
                NSLog(@"Failed to create render pipeline state (QUAD), error %@", renderPipelineError);
                return false;
            }
            
            return true;
        }
        
        void setupBuffers() {
            
            // Allocate memory for the tessellation factors buffer
            // This is a private buffer whose contents are later populated by the GPU (compute kernel)
            this->_tessellationFactorsBuffer = [this->_device newBufferWithLength:256 options:MTLResourceStorageModePrivate];
            this->_tessellationFactorsBuffer.label = @"Tessellation Factors";
            
            // Allocate memory for the control points buffers
            // These are shared or managed buffers whose contents are immediately populated by the CPU
            MTLResourceOptions controlPointsBufferOptions;

            // In OS X, the storage mode can be shared or managed, but managed may yield better performance
            controlPointsBufferOptions = MTLResourceStorageModeManaged;
            
            static const float controlPointPositionsQuad[] = {
                -1.0,  1.0, 0.0, 1.0,   // upper-left
                 1.0,  1.0, 0.0, 1.0,   // upper-right
                 1.0, -1.0, 0.0, 1.0,   // lower-right
                -1.0, -1.0, 0.0, 1.0,   // lower-left
            };
            
            this->_controlPointsBufferQuad = [this->_device newBufferWithBytes:controlPointPositionsQuad length:sizeof(controlPointPositionsQuad) options:controlPointsBufferOptions];
            this->_controlPointsBufferQuad.label = @"Control Points Quad";
            
            // More sophisticated tessellation passes might have additional buffers for per-patch user data
        }
        
        void computeTessellationFactorsWithCommandBuffer(id<MTLCommandBuffer> commandBuffer) {
            
            // Create a compute command encoder
            id <MTLComputeCommandEncoder> computeCommandEncoder = [commandBuffer computeCommandEncoder];
            computeCommandEncoder.label = @"Compute Command Encoder";
            
            // Begin encoding compute commands
            [computeCommandEncoder pushDebugGroup:@"Compute Tessellation Factors"];
            
            // Set the correct compute pipeline
            [computeCommandEncoder setComputePipelineState:this->_computePipelineQuad];
            
            // Bind the tessellation factors buffer to the compute kernel
            [computeCommandEncoder setBuffer:this->_tessellationFactorsBuffer offset:0 atIndex:0];
            
            // Dispatch threadgroups
            [computeCommandEncoder dispatchThreadgroups:MTLSizeMake(1,1,1) threadsPerThreadgroup:MTLSizeMake(1,1,1)];
            
            // All compute commands have been encoded
            [computeCommandEncoder popDebugGroup];
            [computeCommandEncoder endEncoding];
        }

        void tessellateAndRenderInMTKViewWithCommandBuffer(MTKView *view, id<MTLCommandBuffer> commandBuffer) {
            // Obtain a renderPassDescriptor generated from the view's drawable
            MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
            
            // If the renderPassDescriptor is valid, begin the commands to render into its drawable
            if(renderPassDescriptor != nil) {
                // Create a render command encoder
                id <MTLRenderCommandEncoder> renderCommandEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
                renderCommandEncoder.label = @"Render Command Encoder";
                
                // Begin encoding render commands, including commands for the tessellator
                [renderCommandEncoder pushDebugGroup:@"Tessellate and Render"];
                
                // Set the correct render pipeline and bind the correct control points buffer
                [renderCommandEncoder setRenderPipelineState:this->_renderPipelineQuad];
                [renderCommandEncoder setVertexBuffer:this->_controlPointsBufferQuad offset:0 atIndex:0];
                
                // Enable/Disable wireframe mode
                if(this->_wireframe) {
                    [renderCommandEncoder setTriangleFillMode:MTLTriangleFillModeLines];
                }
                
                // Encode tessellation-specific commands
                [renderCommandEncoder setTessellationFactorBuffer:this->_tessellationFactorsBuffer offset:0 instanceStride:0];
                NSUInteger patchControlPoints = 4;
                [renderCommandEncoder drawPatches:patchControlPoints patchStart:0 patchCount:1 patchIndexBuffer:NULL patchIndexBufferOffset:0 instanceCount:1 baseInstance:0];
                
                // All render commands have been encoded
                [renderCommandEncoder popDebugGroup];
                [renderCommandEncoder endEncoding];
                
                // Schedule a present once the drawable has been completely rendered to
                [commandBuffer presentDrawable:view.currentDrawable];
            }
        }

    
    public:
        
        TessellationPipeline(MTKView *view) {
            
            // Initialize properties
            this->_wireframe = true;
            
            // Setup Metal
            if(this->didSetupMetal()) {
                
                // Assign device and delegate to MTKView
                view.device = this->_device;
                
                if(objc_getClass("Delegate")==nil) { objc_registerClassPair(objc_allocateClassPair(objc_getClass("NSObject"),"Delegate",0)); }
                Class Delegate = objc_getClass("Delegate");
                   
                addMethod(Delegate,@"mtkView:drawableSizeWillChange",^(id me,MTKView *view,CGSize size) {
                    NSLog(@"mtkView:drawableSizeWillChange:");
                },"v@:@");
                                
                addMethod(Delegate,@"drawInMTKView:",^(id me,MTKView *view) {
                    NSLog(@"drawInMTKView:"); 
                    @autoreleasepool {
                        // Create a new command buffer for each tessellation pass
                        id <MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
                        commandBuffer.label = @"Tessellation Pass";
                        
                        this->computeTessellationFactorsWithCommandBuffer(commandBuffer);
                        this->tessellateAndRenderInMTKViewWithCommandBuffer(view,commandBuffer);
                        
                        // Finalize tessellation pass and commit the command buffer to the GPU
                        [commandBuffer commit];
                    }
                },"v@:@");
                        
                this->delegate = [[Delegate alloc] init];                
                view.delegate = this->delegate;
                
                // Setup compute pipelines
                if(this->didSetupComputePipelines()) {
                    // Setup render pipelines
                    if(this->didSetupRenderPipelinesWithMTKView(view)) {
                        // Setup Buffers
                        this->setupBuffers();
                    }
                }
            }
        }
        
        ~TessellationPipeline() {
            
        }
};

class App {
    
    private:
    
        NSWindow *win;
        MTKView *view;
        
        TessellationPipeline *tessellationPipeline;
    
    public:
    
        App() {
            
            CGRect rect = CGRectMake(0,0,960,540);
            
            this->win = [[NSWindow alloc] initWithContentRect:rect styleMask:1 backing:NSBackingStoreBuffered defer:NO];
            [this->win center];
            [this->win makeKeyAndOrderFront:nil];
            
            this->view = [[MTKView alloc] initWithFrame:rect];

            [[this->win contentView] addSubview:this->view];
            
            this->view.paused = YES;
            this->view.enableSetNeedsDisplay = YES;
            this->view.sampleCount = 1;
                        
            this->tessellationPipeline = new TessellationPipeline(this->view);
            //[this->view draw];
        }
    
        ~App() {
            [this->win setReleasedWhenClosed:NO];
            [this->win close];
            this->win = nil;
        }
};

#pragma mark AppDelegate
@interface AppDelegate:NSObject <NSApplicationDelegate> {
    App *app;
}
@end
@implementation AppDelegate
-(void)applicationDidFinishLaunching:(NSNotification*)aNotification {
    app = new App();
}
-(void)applicationWillTerminate:(NSNotification *)aNotification {
    delete app;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool {
        id app = [NSApplication sharedApplication];
        id delegat = [AppDelegate alloc];
        [app setDelegate:delegat];
        [app run];
    }
}
