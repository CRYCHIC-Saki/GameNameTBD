# 独立餐桌与凳子 v1

2026-11-06，D059-R3。用户要求凳子远离桌子；内置imagegen以原diner-props-v2.png为参考拆绘，原图只读。最终生成源exec-25ad8eac-d57d-4afd-b407-5af72adf0fb6.png，复制为同名PNG；两列，左为不带前凳的餐桌，右为独立红垫木凳，真实RGBA透明。保留中式木色/红金桌布/两盘菜及俯视像素风，补出原被凳子遮住的桌腿；人物素材未重画。

运行时只读按两格alpha边界取AtlasTexture；桌子与两个凳子分开绘制、共用原家具稳定ID及占格。Imagegen提示强调分离原物件而非重新设计，生成细节仍可能与旧纹理略有差异；实际验收见docs/phases/restaurant-feedback.md R3，不用生成图代替真实场景截图。
