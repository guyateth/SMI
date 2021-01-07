#include "treecast.h"
#include "utils.h"

using namespace clang;

static OperationMetadata extractTreecast(CallExpr* channelDecl)
{
    return OperationMetadata("treecast",
                             extractIntArg(channelDecl, 2),
                             extractDataType(channelDecl, 1),
                             extractBufferSize(channelDecl, 5)
    );
}

OperationMetadata BarrierExtractor::GetOperationMetadata(CallExpr* callExpr)
{
    return extractBarrier(extractChannelDecl(callExpr));
}
std::string BarrierExtractor::CreateDeclaration(const std::string& callName, const OperationMetadata& metadata)
{
    return "void " + this->RenameCall(callName, metadata) + "(SMI_TreecastChannel* chan, void* data);";
}
std::vector<std::string> BarrierExtractor::GetFunctionNames()
{
    return {"SMI_Treecast"};
}

OperationMetadata BarrierChannelExtractor::GetOperationMetadata(CallExpr* callExpr)
{
    return extractBarrier(callExpr);
}
std::string BarrierChannelExtractor::CreateDeclaration(const std::string& callName, const OperationMetadata& metadata)
{
    return this->CreateChannelDeclaration(callName, metadata, "SMI_TreecastChannel", "int count, SMI_Datatype data_type, int port, int root, SMI_Comm comm");
}
std::string BarrierChannelExtractor::GetChannelFunctionName()
{
    return "SMI_Open_treecast_channel";
}
